const std = @import("std");

const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;
const debug = @import("./debug.zig");

const gpa = std.heap.page_allocator;

pub fn main() !void {
    var chunk: Chunk = .init();
    defer chunk.deinit(gpa);

    const constant = try chunk.addConstant(gpa, 1.2);
    try chunk.write(gpa, @intFromEnum(OpCode.CONSTANT), 123);
    try chunk.write(gpa, constant, 123);

    try chunk.write(gpa, @intFromEnum(OpCode.RETURN), 123);
    debug.disassembleChunk(&chunk, "test chunk");
}
