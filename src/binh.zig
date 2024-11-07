const std = @import("std");

const tpl =
    \\#include <stddef.h>
    \\
    \\const unsigned char {s}[] = {{
    \\{s}}};
    \\const size_t {s}_SIZE = {d};
    \\
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    const stderr = std.io.getStdErr();
    defer std.process.argsFree(allocator, args);
    if (args.len != 4) {
        _ = try stderr.write("usage: binh <binfile> <name> <output>\n");
        return error.Needs3ArgumentsExact;
    }
    const file = try std.fs.cwd().readFileAlloc(allocator, args[1], std.math.maxInt(u64));
    defer allocator.free(file);

    var content = std.ArrayList(u8).init(allocator);
    defer content.deinit();

    var cbuf: [6]u8 = undefined;
    for (file, 1..) |char, i| {
        const cslice = try std.fmt.bufPrint(
            &cbuf,
            "0x{}, ",
            .{std.fmt.fmtSliceHexLower(&.{char})},
        );
        try content.appendSlice(cslice);
        if ((i % 16) == 0) {
            try content.append('\n');
        }
    }

    var output = try std.fs.cwd().createFile(args[3], .{});
    defer output.close();
    try output.writer().print(tpl, .{
        args[2],
        content.items,
        args[2],
        file.len,
    });
}
