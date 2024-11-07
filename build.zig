const std = @import("std");
const builtin = @import("builtin");

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
    });
    const binh = b.addExecutable(.{
        .name = "binh",
        .root_source_file = b.path("src/binh.zig"),
        .target = b.host,
        .optimize = optimize,
    });
    b.installArtifact(binh);

    if (b.lazyDependency("picotool", .{
        .target = target,
        .optimize = optimize,
    })) |picotool_src| {
        const rp2350_rom = b.addRunArtifact(binh);
        rp2350_rom.addFileArg(picotool_src.path("bootrom.end.bin"));
        rp2350_rom.addArg("rp2350_rom");
        const rp2350_h = rp2350_rom.addOutputFileArg("rp2350.rom.h");
        const rp2350_rom_install = b.addInstallFile(
            rp2350_h,
            "include/rp2350.rom.h",
        );
        const generate_headers = b.step("generate_headers", "");
        generate_headers.dependOn(&rp2350_rom_install.step);

        const xip_ram_perms_elf = b.addRunArtifact(binh);
        xip_ram_perms_elf.addFileArg(picotool_src.path("xip_ram_perms/xip_ram_perms.elf"));
        xip_ram_perms_elf.addArg("xip_ram_perms_elf");
        const xip_ram_perms_elf_h = xip_ram_perms_elf.addOutputFileArg("xip_ram_perms_elf.h");
        const xip_ram_perms_elf_install = b.addInstallFile(
            xip_ram_perms_elf_h,
            "include/xip_ram_perms_elf.h",
        );
        generate_headers.dependOn(&xip_ram_perms_elf_install.step);

        const data_locs = b.addConfigHeader(.{
            .style = .{ .cmake = picotool_src.path("data_locs.template.cpp") },
            .include_path = "data_locs.cpp",
        }, .{
            .DATA_LOCS_VEC = "",
        });

        const elf2uf2 = b.addStaticLibrary(.{
            .name = "elf2uf2",
            .target = target,
            .optimize = optimize,
        });
        elf2uf2.linkLibCpp();
        elf2uf2.addCSourceFiles(.{
            .files = &.{"elf2uf2.cpp"},
            .root = picotool_src.path("elf2uf2"),
        });
        elf2uf2.addIncludePath(picotool_src.path("elf2uf2"));

        const picotool = b.addExecutable(.{
            .name = "picotool",
            .target = target,
            .optimize = optimize,
        });
        // picotool.linkLibC();
        picotool.linkLibCpp();
        picotool.addCSourceFile(.{ .file = data_locs.getOutput() });
        picotool.addCSourceFiles(.{
            .files = &.{
                "main.cpp",
                "otp.cpp",
                "xip_ram_perms.cpp",
                "bintool/bintool.cpp",
                "elf/elf_file.cpp",
                "errors/errors.cpp",
                "lib/whereami/whereami++.cpp",
                "picoboot_connection/picoboot_connection_cxx.cpp",
                "picoboot_connection/picoboot_connection.c",
            },
            .root = picotool_src.path(""),
        });
        picotool.defineCMacro("SYSTEM_VERSION", "\"2.0.0\"");
        picotool.defineCMacro("PICOTOOL_VERSION", "\"2.0.0\"");
        picotool.defineCMacro("COMPILER_INFO", "\"zig-" ++ builtin.zig_version_string ++ "\"");
        picotool.defineCMacro("HAS_LIBUSB", "1");
        picotool.linkLibrary(libusb.artifact("usb"));
        picotool.addIncludePath(rp2350_h.dirname());
        picotool.addIncludePath(xip_ram_perms_elf_h.dirname());
        // picotool.root_module.addImport("sdk", sdk_module);
        // picotool.linkSystemLibrary("algorithm");
        inline for (.{
            "",
            "bintool",
            "elf",
            "elf2uf2",
            "errors",
            "lib/nlohmann_json/single_include",
            "lib/whereami",
            "otp_header_parser",
            "picoboot_connection",
        }) |include_path| {
            const picotool_path = picotool_src.path(include_path);
            elf2uf2.addIncludePath(picotool_path);
            picotool.addIncludePath(picotool_path);
        }
        // picotool.addIncludePath(picotool_src.path(""));
        // picotool.addIncludePath(picotool_src.path("elf"));
        // picotool.addIncludePath(picotool_src.path("bintool"));
        // picotool.addIncludePath(picotool_src.path("picoboot_connection"));
        inline for (.{
            "src/common/boot_picobin_headers/include",
            "src/common/boot_picoboot_headers/include",
            "src/common/boot_uf2_headers/include",
            "src/common/pico_binary_info/include",
            "src/common/pico_usb_reset_interface_headers/include",
            "src/host/pico_platform/include",
            "src/rp2_common/pico_bootrom/include",
            "src/rp2_common/pico_stdio_usb/include",
            "src/rp2350/hardware_regs/include",
        }) |include_path| {
            const pico_sdk_path = pico_sdk.path(include_path);
            elf2uf2.addIncludePath(pico_sdk_path);
            picotool.addIncludePath(pico_sdk_path);
        }
        picotool.linkLibrary(elf2uf2);
        b.installArtifact(picotool);

        const run_picotool = b.addRunArtifact(picotool);
        if (b.args) |args| {
            run_picotool.addArgs(args);
        }
        run_step.dependOn(&run_picotool.step);
    }
}
