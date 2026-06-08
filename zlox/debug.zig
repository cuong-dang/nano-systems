const print = @import("std").debug.print;

const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;
const printValue = @import("./value.zig").printValue;

pub fn disassembleChunk(chunk: *Chunk, name: []const u8) void {
    print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunk.count()) {
        offset = disassembleInstruction(chunk, offset);
    }
}

pub fn disassembleInstruction(chunk: *Chunk, offset: usize) usize {
    print("{d:0>4} ", .{offset});
    if (offset > 0 and chunk.lineOf(offset) == chunk.lineOf(offset - 1)) {
        print("   | ", .{});
    } else {
        print("{d:>4} ", .{chunk.lineOf(offset)});
    }

    const op: OpCode = @enumFromInt(chunk.get(offset));
    switch (op) {
        .CONSTANT => return constantInstruction(.CONSTANT, chunk, offset),
        .GET_LOCAL => return byteInstruction(.GET_LOCAL, chunk, offset),
        .SET_LOCAL => return byteInstruction(.SET_LOCAL, chunk, offset),
        .GET_GLOBAL => return constantInstruction(.GET_GLOBAL, chunk, offset),
        .SET_GLOBAL => return constantInstruction(.SET_GLOBAL, chunk, offset),
        .DEFINE_GLOBAL => return constantInstruction(.DEFINE_GLOBAL, chunk, offset),
        .JUMP_IF_FALSE => return shortInstruction(.JUMP_IF_FALSE, chunk, offset),
        else => |v| return simpleInstruction(v, offset),
    }
}

fn simpleInstruction(op: OpCode, offset: usize) usize {
    print("{s}\n", .{@tagName(op)});
    return offset + 1;
}

fn constantInstruction(op: OpCode, chunk: *Chunk, offset: usize) usize {
    const constant = chunk.get(offset + 1);
    print("{s:<16} {d:>4} '", .{ @tagName(op), constant });
    printValue(chunk.getConstant(constant));
    print("'\n", .{});
    return offset + 2;
}

fn byteInstruction(op: OpCode, chunk: *Chunk, offset: usize) usize {
    const slot = chunk.get(offset + 1);
    print("{s:<16} {d:>4}\n", .{ @tagName(op), slot });
    return offset + 2;
}

fn shortInstruction(op: OpCode, chunk: *Chunk, offset: usize) usize {
    const short: u16 = (@as(u16, chunk.get(offset + 1)) << 8) | @as(u16, chunk.get(offset + 2));
    print("{s:<16} {d:>4}\n", .{ @tagName(op), short });
    return offset + 3;
}
