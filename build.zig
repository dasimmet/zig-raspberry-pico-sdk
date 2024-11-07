const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
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

    if (b.lazyDependency("picotool", .{
        .target = target,
        .optimize = optimize,
    })) |picotool_src| {
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
        // elf2uf2.installHeadersDirectory(picotool_src.path("elf2uf2"), "include", .{});

        const picotool = b.addExecutable(.{
            .name = "picotool",
            .target = target,
            .optimize = optimize,
        });
        // picotool.linkLibC();
        picotool.linkLibCpp();
        picotool.addCSourceFiles(.{
            .files = &.{
                "main.cpp",
                "bintool/bintool.cpp",
                "errors/errors.cpp",
                "elf/elf_file.cpp",
            },
            .root = picotool_src.path(""),
        });
        picotool.defineCMacro("SYSTEM_VERSION", "\"2.0.0\"");
        picotool.defineCMacro("PICOTOOL_VERSION", "\"2.0.0\"");
        picotool.defineCMacro("COMPILER_INFO", "\"zig-" ++ builtin.zig_version_string ++ "\"");
        // picotool.root_module.addImport("sdk", sdk_module);
        // picotool.linkSystemLibrary("algorithm");
        inline for (.{
            "",
            "bintool",
            "elf",
            "elf2uf2",
            "errors",
            "lib/nlohmann_json/single_include",
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
    }
}
