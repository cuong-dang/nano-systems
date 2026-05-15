const std = @import("std");

const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;

pub fn disassembleChunk(chunk: *Chunk, name: []const u8) void {
    std.debug.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunk.count()) {
        offset = disassembleInstruction(chunk, offset);
    }
}

fn disassembleInstruction(chunk: *Chunk, offset: usize) usize {
    std.debug.print("{d:0>4} ", .{offset});
    switch (chunk.get(offset)) {
        @intFromEnum(OpCode.RETURN) => return simpleInstruction(OpCode.RETURN, offset),
        else => {
            std.debug.print("Unknown opcode {}\n", .{chunk.get(offset)});
            return offset + 1;
        },
    }
}

fn simpleInstruction(op: OpCode, offset: usize) usize {
    std.debug.print("{s}\n", .{@tagName(op)});
    return offset + 1;
}
