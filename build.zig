const std = @import("std");
const builtin = @import("builtin");

pub const LoadOptions = struct {
    // firmware file to load
    firmware: std.Build.LazyPath,
    // try rebooting into BOOTSEL before flashing
    force: bool = false,
    // reboot into program after flashing
    execute: bool = false,
    // use sudo if usb device is requires elevated permissions
    sudo: bool = false,
    // device-selection
    bus: ?[]const u8 = null,
    address: ?[]const u8 = null,
    vid: ?[]const u8 = null,
    pid: ?[]const u8 = null,
};

// load a firmware file to the default raspi pico found connected on usb
pub fn load(b: *std.Build, opt: LoadOptions, args: anytype) *std.Build.Step.Run {
    const this_dep = b.dependencyFromBuildZig(@This(), args);
    const flash_step = std.Build.Step.Run.create(b, "picotool");
    if (opt.sudo) {
        flash_step.addArg("sudo");
    }
    flash_step.addFileArg(this_dep.artifact("picotool"));
    flash_step.addArg("load");
    flash_step.addFileArg(opt.firmware);

    if (opt.force) {
        flash_step.addArg("--force");
    }
    if (opt.execute) {
        flash_step.addArg("--execute");
    }
    if (opt.bus) |bus| {
        flash_step.addArgs(&.{ "--bus", bus });
    }
    if (opt.address) |address| {
        flash_step.addArgs(&.{ "--address", address });
    }
    if (opt.vid) |vid| {
        flash_step.addArgs(&.{ "--vid", vid });
    }
    if (opt.pid) |pid| {
        flash_step.addArgs(&.{ "--pid", pid });
    }
    return flash_step;
}

pub fn build(b: *std.Build) void {
    const run_step = b.step("run", "run picotool");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const backup_package_sources = b.option(bool, "package_backup", "package_backup") orelse false;
    if (backup_package_sources) {
        const global_cache: std.Build.LazyPath = .{ .cwd_relative = b.graph.global_cache_root.path.? };
        b.installDirectory(.{
            .source_dir = global_cache.path(b, "p"),
            .install_dir = .{ .custom = "packages" },
            .install_subdir = "",
        });
    }

    const sdk_module = b.addModule("sdk", .{
        .root_source_file = b.path("src/sdk.zig"),
        .target = target,
        .optimize = optimize,
    });
    _ = sdk_module;

    const pico_sdk = b.dependency("pico-sdk", .{
        .target = target,
        .optimize = optimize,
    });
    const libusb = b.dependency("libusb", .{
        .target = target,
        .optimize = b.option(
            std.builtin.OptimizeMode,
            "optimize-libusb",
            "optimize mode for libusb, defaults to ReleaseFast",
        ) orelse .ReleaseFast,
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
    b.step("binh", "install binh binary").dependOn(
        &b.addInstallArtifact(binh, .{}).step,
    );

    if (b.lazyDependency("picotool", .{
        .target = target,
        .optimize = optimize,
    })) |picotool_src| {
        const generate_headers = b.step(
            "generate_headers",
            "install the generated binh headers",
        );
        const xip_ram_perms_elf_h = generate_header(
            b,
            binh,
            picotool_src.path("xip_ram_perms/xip_ram_perms.elf"),
            "xip_ram_perms_elf",
            "xip_ram_perms_elf.h",
        );
        generate_headers.dependOn(&b.addInstallFile(
            xip_ram_perms_elf_h,
            "include/xip_ram_perms_elf.h",
        ).step);

        const flash_id_bin_h = generate_header(
            b,
            binh,
            picotool_src.path("picoboot_flash_id/flash_id.bin"),
            "flash_id_bin",
            "flash_id_bin.h",
        );
        generate_headers.dependOn(&b.addInstallFile(
            flash_id_bin_h,
            "include/flash_id_bin.h",
        ).step);

        const data_locs = b.addConfigHeader(.{
            .style = .{ .cmake = picotool_src.path("data_locs.template.cpp") },
            .include_path = "data_locs.cpp",
        }, .{
            .DATA_LOCS_VEC = "",
        });

        //elf2uf2
        const elf2uf2 = b.addLibrary(.{
            .name = "elf2uf2",
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
            }),
        });
        elf2uf2.linkLibCpp();
        elf2uf2.addCSourceFiles(.{
            .files = &.{"elf2uf2.cpp"},
            .root = picotool_src.path("elf2uf2"),
            .flags = &cppflags,
        });

        inline for (.{
            "elf",
            "errors",
            "model",
        }) |include_path| {
            const picotool_path = picotool_src.path(include_path);
            elf2uf2.addIncludePath(picotool_path);
        }
        inline for (.{
            "src/common/boot_picoboot_headers/include",
            "src/common/boot_uf2_headers/include",
            "src/host/pico_platform/include",
        }) |include_path| {
            const pico_sdk_path = pico_sdk.path(include_path);
            elf2uf2.addIncludePath(pico_sdk_path);
        }

        //picotool
        const picotool = b.addExecutable(.{
            .name = "picotool",
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
            }),
        });
        picotool.linkLibCpp();
        picotool.addCSourceFile(.{
            .file = data_locs.getOutput(),
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

        inline for (.{
            .{ "SYSTEM_VERSION", "\"2.2.0\"" },
            .{ "PICOTOOL_VERSION", "\"2.2.0-a4\"" },
            .{ "COMPILER_INFO", "\"zig-" ++ builtin.zig_version_string ++ "\"" },
            .{ "_CLANG_DISABLE_CRT_DEPRECATION_WARNINGS", "1" },
        }) |macro| {
            picotool.root_module.addCMacro(macro[0], macro[1]);
        }

        picotool.root_module.addCMacro("HAS_LIBUSB", "1");
        picotool.linkLibrary(libusb.artifact("usb"));
        picotool.linkLibrary(elf2uf2);

        inline for (&.{
            "rp2350_a2_rom_end",
            "rp2350_a3_rom_end",
            "rp2350_a4_rom_end",
        }) |bin_h_name| {
            const rp2350_h = generate_header(
                b,
                binh,
                picotool_src.path("model/" ++ bin_h_name ++ ".bin"),
                bin_h_name,
                bin_h_name ++ ".h",
            );
            generate_headers.dependOn(&b.addInstallFile(
                rp2350_h,
                "include/rp2350.rom.h",
            ).step);
            picotool.addIncludePath(rp2350_h.dirname());
            elf2uf2.addIncludePath(rp2350_h.dirname());
        }

        picotool.addIncludePath(xip_ram_perms_elf_h.dirname());
        picotool.addIncludePath(flash_id_bin_h.dirname());

        inline for (.{
            "",
            "bintool",
            "elf",
            "elf2uf2",
            "errors",
            "lib/nlohmann_json/single_include",
            "lib/whereami",
            "model",
            "otp_header_parser",
            "picoboot_connection",
        }) |include_path| {
            const picotool_path = picotool_src.path(include_path);
            picotool.addIncludePath(picotool_path);
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
        b.installArtifact(picotool);

        const run_picotool = b.addRunArtifact(picotool);
        if (b.args) |args| {
            run_picotool.addArgs(args);
        }
        run_step.dependOn(&run_picotool.step);

        const udev_rules = b.addInstallFile(
            picotool_src.path("udev/60-picotool.rules"),
            "etc/udev/rules.d/60-picotool.rules",
        );
        b.getInstallStep().dependOn(&udev_rules.step);
        b.step("udev", "install the raspberry udev rules").dependOn(&udev_rules.step);
    }
}

pub const cppflags = .{
    "-std=c++23",
} ++ commonflags;

pub const cflags = .{
    "-std=c23",
    // "-pedantic",
} ++ commonflags;

pub const commonflags = .{
    "-fsanitize=undefined",
    "-fsanitize-trap=undefined",
    "-fsanitize=bounds",
    "-Wall",
    "-Wextra",
    "-g",
    "-Werror",
    "-Wno-delete-non-abstract-non-virtual-dtor",
    "-Wno-enum-enum-conversion",
    "-Wno-format",
    "-Wno-newline-eof",
    "-Wno-reorder",
    "-Wno-sign-compare",
    "-Wno-unsequenced",
    "-Wno-unused-but-set-variable",
    "-Wno-unused-const-variable",
    "-Wno-unused-function",
    "-Wno-unused-parameter",
    "-Wno-unused-variable",
    "-Wno-zero-length-array",
};

pub fn generate_header(
    b: *std.Build,
    binh: *std.Build.Step.Compile,
    input: std.Build.LazyPath,
    name: []const u8,
    out_basename: []const u8,
) std.Build.LazyPath {
    const run_step = b.addRunArtifact(binh);
    run_step.addFileArg(input);
    run_step.addArg(name);
    return run_step.addOutputFileArg(out_basename);
}
