const std = @import("std");

const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;
const printValue = @import("./chunk.zig").printValue;

pub fn disassembleChunk(chunk: *Chunk, name: []const u8) void {
    std.debug.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunk.count()) {
        offset = disassembleInstruction(chunk, offset);
    }
}

fn disassembleInstruction(chunk: *Chunk, offset: usize) usize {
    std.debug.print("{d:0>4} ", .{offset});
    const op: OpCode = @enumFromInt(chunk.get(offset));
    switch (op) {
        .CONSTANT => return constantInstruction(OpCode.CONSTANT, chunk, offset),
        .RETURN => return simpleInstruction(OpCode.RETURN, offset),
    }
}

fn simpleInstruction(op: OpCode, offset: usize) usize {
    std.debug.print("{s}\n", .{@tagName(op)});
    return offset + 1;
}

fn constantInstruction(op: OpCode, chunk: *Chunk, offset: usize) usize {
    const constant = chunk.get(offset + 1);
    std.debug.print("{s:<16} {d:>4} '", .{ @tagName(op), constant });
    printValue(chunk.getConstant(constant));
    std.debug.print("'\n", .{});
    return offset + 2;
}
