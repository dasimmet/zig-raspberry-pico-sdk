const std = @import("std");

const usage =
    \\
    \\converts a binfile to a C .h file with a bytestring const literal and length
    \\usage: binh <binfile> <name> <output>
    \\binfile: any input binary file
    \\name: name of the literal. The length will be named <name>_SIZE
    \\
    \\
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    const stderr = std.fs.File.stderr();
    defer std.process.argsFree(allocator, args);
    if (args.len != 4) {
        _ = try stderr.write(usage);
        return error.Needs3ArgumentsExact;
    }
    const file = try std.fs.cwd().openFile(args[1], .{});
    defer file.close();

    var output = try std.fs.cwd().createFile(args[3], .{});
    defer output.close();
    var out_buf: [1048576]u8 = undefined;
    var out_writer = output.writer(&out_buf);
    try out_writer.interface.print(template_pre, .{
        args[2],
    });

    var buf: [64]u8 = undefined;
    var slice: []u8 = buf[0..try file.read(&buf)];
    var count: usize = 0;
    while (slice.len > 0) : (slice = buf[0..try file.read(&buf)]) {
        count += slice.len;
        for (slice, 1..) |char, i| {
            try out_writer.interface.print(
                "0x{x}, ",
                .{char},
            );
            if ((i % 16) == 0) {
                _ = try out_writer.interface.write("\n");
            }
        }
    }
    try out_writer.interface.print(template_post, .{
        args[2],
        count,
    });
    try out_writer.interface.flush();
}

const template_pre =
    \\#include <stddef.h>
    \\
    \\const unsigned char {s}[] = {{
    \\
;

const template_post =
    \\}};
    \\const size_t {s}_SIZE = {d};
    \\
;
