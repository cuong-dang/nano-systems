const std = @import("std");

const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;
const debug = @import("./debug.zig");

const gpa = std.heap.page_allocator;

pub fn main() !void {
    var chunk: Chunk = .init();
    defer chunk.deinit(gpa);

    try chunk.write(gpa, @intFromEnum(OpCode.RETURN));
    debug.disassembleChunk(&chunk, "test chunk");
}
