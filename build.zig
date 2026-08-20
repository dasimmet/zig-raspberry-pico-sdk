const std = @import("std");
const builtin = @import("builtin");
const build_zon = @import("build.zig.zon");
const Build = std.Build;
const LazyPath = Build.LazyPath;
const Run = Build.Step.Run;
const Compile = Build.Step.Compile;
const OptimizeMode = std.builtin.OptimizeMode;

const pico_sdk_version = build_zon.version;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const data_locs = b.option(
        []const u8,
        "data-locs",
        "semicolon separated runtime data locations",
    ) orelse "./;/usr/local/share/picotool";

    const ci_step = b.step("ci", "build picotool for ci targets");

    const picotool_src = b.dependency("picotool", .{});
    const udev_rules = b.addInstallFile(
        picotool_src.path("udev/60-picotool.rules"),
        "etc/udev/rules.d/60-picotool.rules",
    );
    b.getInstallStep().dependOn(&udev_rules.step);
    ci_step.dependOn(&udev_rules.step);
    b.step("udev", "install the raspberry udev rules").dependOn(&udev_rules.step);

    const picotool_exe = buildWithOptions(
        b,
        target,
        optimize,
        data_locs,
        true,
    );
    b.installArtifact(picotool_exe);

    const run_picotool = b.addRunArtifact(picotool_exe);
    passthroughArgs(b, run_picotool);
    const run_step = b.step("run", "run picotool");
    run_step.dependOn(&run_picotool.step);

    inline for (&.{
        "x86_64-linux-gnu",
        "x86_64-linux-musl",
        "aarch64-linux-gnu",
        "aarch64-linux-musl",
        "x86_64-windows-gnu",
        "aarch64-windows-gnu",
    }) |target_str| {
        const ci_target = b.resolveTargetQuery(std.Target.Query.parse(.{ .arch_os_abi = target_str }) catch unreachable);
        const exe = buildWithOptions(
            b,
            ci_target,
            optimize,
            data_locs,
            false,
        );
        const ci_install = b.addInstallArtifact(exe, .{
            .dest_dir = .{ .override = .{ .custom = "bin/" ++ target_str } },
        });

        ci_step.dependOn(&ci_install.step);
    }
}

fn buildWithOptions(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: OptimizeMode,
    data_locs: []const u8,
    global_steps: bool,
) *Compile {
    const pico_sdk = b.dependency("pico-sdk", .{});
    const picotool_src = b.dependency("picotool", .{});
    const libusb = b.dependency("libusb", .{
        .target = target,
        .optimize = optimize,
        .@"system-libudev" = false,
    });

    const binh = b.addExecutable(.{
        .name = "binh",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/binh.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
    });
    const xip_ram_perms_elf_h = generate_binh(
        b,
        binh,
        picotool_src.path("xip_ram_perms/xip_ram_perms.elf"),
        "xip_ram_perms_elf",
        "xip_ram_perms_elf.h",
    );

    const flash_id_bin_h = generate_binh(
        b,
        binh,
        picotool_src.path("picoboot_flash_id/flash_id.bin"),
        "flash_id_bin",
        "flash_id_bin.h",
    );

    const data_locs_vec = b.fmt("{f}", .{
        DataLocsFmt.fmt(data_locs),
    });

    const data_locs_h = b.addConfigHeader(.{
        .style = .{ .cmake = picotool_src.path("data_locs.template.cpp") },
        .include_path = "data_locs.cpp",
    }, .{
        .DATA_LOCS_VEC = data_locs_vec,
    });

    //elf2uf2
    const elf2uf2 = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
    });
    const libelf2uf2 = b.addLibrary(.{
        .name = "elf2uf2",
        .root_module = elf2uf2,
    });

    elf2uf2.addCSourceFiles(.{
        .files = &.{"elf2uf2.cpp"},
        .root = picotool_src.path("elf2uf2"),
        .flags = &cppflags,
    });
    libelf2uf2.installHeadersDirectory(
        picotool_src.path("elf2uf2"),
        "",
        .{},
    );

    inline for (.{
        "elf",
        "errors",
        "model",
    }) |include_path| {
        elf2uf2.addIncludePath(picotool_src.path(include_path));
    }

    inline for (.{
        "src/common/boot_picoboot_headers/include",
        "src/common/boot_uf2_headers/include",
        "src/host/pico_platform/include",
    }) |include_path| {
        elf2uf2.addIncludePath(pico_sdk.path(include_path));
    }

    //oofatfs
    const oofatfs = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const liboofatfs = b.addLibrary(.{
        .name = "oofatfs",
        .root_module = oofatfs,
    });
    oofatfs.addCSourceFiles(.{
        .root = picotool_src.path("lib/oofatfs/src"),
        .files = &.{
            "ff.c",
            "ffunicode.c",
        },
        .flags = &cflags,
    });
    oofatfs.addIncludePath(picotool_src.path("lib/oofatfs/src"));
    liboofatfs.installHeadersDirectory(
        picotool_src.path("lib/oofatfs/src"),
        "",
        .{},
    );

    //littlefs
    const littlefs = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const liblittlefs = b.addLibrary(.{
        .name = "littlefs",
        .root_module = littlefs,
    });
    littlefs.addCSourceFiles(.{
        .root = picotool_src.path("lib/littlefs"),
        .files = &.{
            "lfs.c",
            "lfs_util.c",
        },
        .flags = &cflags,
    });
    littlefs.addIncludePath(picotool_src.path("lib/littlefs"));
    liblittlefs.installHeadersDirectory(
        picotool_src.path("lib/littlefs"),
        "",
        .{},
    );

    //picotool
    const picotool = b.createModule(.{
        .target = target,
        .optimize = optimize,
    });
    const picotool_exe = b.addExecutable(.{
        .name = "picotool",
        .root_module = picotool,
    });

    picotool.addCSourceFile(.{
        .file = data_locs_h.getOutputFile(),
        .flags = &cppflags,
    });
    picotool.addCSourceFiles(.{
        .files = &.{
            "main.cpp",
            "model/model.cpp",
            "otp.cpp",
            "get_xip_ram_perms.cpp",
            "bintool/bintool.cpp",
            "elf/elf_file.cpp",
            "errors/errors.cpp",
            "lib/whereami/whereami++.cpp",
            "picoboot_connection/picoboot_connection_cxx.cpp",
        },
        .root = picotool_src.path(""),
        .flags = &cppflags,
    });
    picotool.addCSourceFiles(.{
        .files = &.{
            "picoboot_connection/picoboot_connection.c",
        },
        .root = picotool_src.path(""),
        .flags = &cflags,
    });

    const pico_sdk_version_escaped = b.fmt("\"{s}\"", .{pico_sdk_version});
    inline for (.{
        .{ "SYSTEM_VERSION", pico_sdk_version_escaped },
        .{ "PICOTOOL_VERSION", pico_sdk_version_escaped },
        .{ "COMPILER_INFO", "\"zig-" ++ builtin.zig_version_string ++ "\"" },
        .{ "_CLANG_DISABLE_CRT_DEPRECATION_WARNINGS", "1" },
    }) |macro| {
        picotool.addCMacro(macro[0], macro[1]);
    }

    picotool.addCMacro("HAS_LIBUSB", "1");
    picotool.linkLibrary(libusb.artifact("usb"));
    picotool.linkLibrary(libelf2uf2);
    picotool.linkLibrary(liboofatfs);
    picotool.linkLibrary(liblittlefs);

    const generate_headers = generate_headers: {
        if (global_steps) {
            b.step("binh", "install binh binary").dependOn(
                &b.addInstallArtifact(binh, .{}).step,
            );
            const generate_headers = b.step(
                "generate_headers",
                "install the generated binh headers",
            );
            generate_headers.dependOn(&b.addInstallHeaderFile(
                xip_ram_perms_elf_h,
                "xip_ram_perms_elf.h",
            ).step);
            generate_headers.dependOn(&b.addInstallHeaderFile(
                flash_id_bin_h,
                "flash_id_bin.h",
            ).step);
            break :generate_headers generate_headers;
        }
        break :generate_headers null;
    };

    inline for (&.{
        "rp2350_a2_rom_end",
        "rp2350_a3_rom_end",
        "rp2350_a4_rom_end",
    }) |bin_h_name| {
        const model_h_name = bin_h_name ++ ".h";
        const model_h = generate_binh(
            b,
            binh,
            picotool_src.path("model/" ++ bin_h_name ++ ".bin"),
            bin_h_name,
            model_h_name,
        );
        if (generate_headers) |gh| {
            gh.dependOn(&b.addInstallHeaderFile(
                model_h,
                model_h_name,
            ).step);
        }
        picotool.addIncludePath(model_h.dirname());
        elf2uf2.addIncludePath(model_h.dirname());
    }

    picotool.addIncludePath(xip_ram_perms_elf_h.dirname());
    picotool.addIncludePath(flash_id_bin_h.dirname());

    inline for (.{
        "",
        "bintool",
        "elf",
        "errors",
        "lib/nlohmann_json/single_include",
        "lib/whereami",
        "model",
        "otp_header_parser",
        "picoboot_connection",
    }) |include_path| {
        picotool.addIncludePath(picotool_src.path(include_path));
    }

    inline for (.{
        "src/common/boot_picobin_headers/include",
        "src/common/boot_picoboot_headers/include",
        "src/common/boot_uf2_headers/include",
        "src/common/pico_binary_info/include",
        "src/common/pico_usb_reset_interface_headers/include",
        "src/host/pico_platform/include",
        "src/rp2_common/boot_bootrom_headers/include",
        "src/rp2_common/pico_stdio_usb/include",
        "src/rp2350/hardware_regs/include",
    }) |include_path| {
        const pico_sdk_path = pico_sdk.path(include_path);
        picotool.addIncludePath(pico_sdk_path);
    }

    return picotool_exe;
}

pub const DataLocsFmt = struct {
    src: []const u8,

    pub fn fmt(src: []const u8) DataLocsFmt {
        return .{ .src = src };
    }

    pub fn format(self: *const @This(), w: *std.Io.Writer) !void {
        for (self.src) |c| {
            if (c == ';') {
                @branchHint(.unlikely);
                try w.writeAll("\",\"");
                continue;
            }
            try w.writeAll(&.{c});
        }
    }
};

pub const cppflags = .{
    "-std=c++23",
    "-fuse-cxa-atexit",
} ++ commonflags;

pub const cflags = .{
    "-std=c23",
    "-pedantic",
} ++ commonflags;

pub const commonflags = .{
    "-fsanitize=undefined",
    "-fsanitize-trap=undefined",
    "-fsanitize=bounds",
    "-Wall",
    "-Wextra",
    "-g",
    "-Werror",
    "-Wno-error=delete-non-abstract-non-virtual-dtor",
    "-Wno-error=enum-enum-conversion",
    "-Wno-error=format",
    "-Wno-error=missing-field-initializers",
    "-Wno-error=newline-eof",
    "-Wno-error=reorder",
    "-Wno-error=sign-compare",
    "-Wno-error=unsequenced",
    "-Wno-error=unused-but-set-variable",
    "-Wno-error=unused-command-line-argument",
    "-Wno-error=unused-const-variable",
    "-Wno-error=unused-function",
    "-Wno-error=unused-parameter",
    "-Wno-error=unused-variable",
    "-Wno-error=zero-length-array",
};

pub fn generate_binh(
    b: *Build,
    binh: *Compile,
    input: LazyPath,
    name: []const u8,
    out_basename: []const u8,
) LazyPath {
    const run_step = b.addRunArtifact(binh);
    run_step.addFileArg(input);
    run_step.addArg(name);
    return run_step.addOutputFileArg(out_basename);
}

// zig 0.17.0 and 0.16.0 compatible args passthrough function
inline fn passthroughArgs(b: *Build, run: *Run) void {
    if (comptime @import("builtin").zig_version.order(std.SemanticVersion.parse("0.16.0") catch unreachable) == .gt) {
        run.addPassthruArgs();
    } else {
        if (b.args) |args| {
            for (args) |arg| run.addArg(arg);
        }
    }
}
