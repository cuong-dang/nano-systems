const std = @import("std");

pub const Chunk = struct {
    _code: std.ArrayList(u8),
    constants: std.ArrayList(Value),
    lineInfo: std.ArrayList(LineInfo),

    pub fn init() Chunk {
        return .{ ._code = .empty, .constants = .empty, .lineInfo = .empty };
    }

    pub fn deinit(self: *Chunk, gpa: std.mem.Allocator) void {
        self._code.deinit(gpa);
        self.constants.deinit(gpa);
        self.lineInfo.deinit(gpa);
    }

    pub fn count(self: *const Chunk) usize {
        return self._code.items.len;
    }

    pub fn get(self: *const Chunk, offset: usize) u8 {
        return self._code.items[offset];
    }

    pub fn getConstant(self: *const Chunk, constant: usize) Value {
        return self.constants.items[constant];
    }

    pub fn lineOf(self: *const Chunk, offset: usize) usize {
        if (self.lineInfo.items.len == 1) return self.lineInfo.items[0].line;
        for (self.lineInfo.items, 1..) |lineInfo, i| {
            if (offset < lineInfo.offset) {
                return self.lineInfo.items[i - 1].line;
            }
        }
        return self.lineInfo.items[self.lineInfo.items.len - 1].line;
    }

    pub fn code(self: *const Chunk) [*]const u8 {
        return self._code.items.ptr;
    }

    pub fn write(self: *Chunk, gpa: std.mem.Allocator, byte: u8, line: usize) !void {
        try self._code.append(gpa, byte);
        if (self.lineInfo.items.len == 0 or
            self.lineInfo.items[self.lineInfo.items.len - 1].line != line)
        {
            try self.lineInfo.append(gpa, .{ .offset = self._code.items.len - 1, .line = line });
        }
    }

    pub fn addConstant(self: *Chunk, gpa: std.mem.Allocator, value: Value) !usize {
        try self.constants.append(gpa, value);
        return self.constants.items.len - 1;
    }
};

pub const OpCode = enum {
    CONSTANT,
    ADD,
    SUBTRACT,
    MULTIPLY,
    DIVIDE,
    NEGATE,
    RETURN,
};

pub const Value = f64;

pub fn printValue(value: Value) void {
    std.debug.print("{}", .{value});
}

const LineInfo = struct {
    offset: usize,
    line: usize,
};
