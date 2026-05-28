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
