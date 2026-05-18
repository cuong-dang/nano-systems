const std = @import("std");

pub const Chunk = struct {
    _code: std.ArrayList(u8),
    _constants: std.ArrayList(Value),
    _lineInfo: std.ArrayList(LineInfo),

    pub fn init() Chunk {
        return .{ ._code = .empty, ._constants = .empty, ._lineInfo = .empty };
    }

    pub fn deinit(self: *Chunk, gpa: std.mem.Allocator) void {
        self._code.deinit(gpa);
        self._constants.deinit(gpa);
        self._lineInfo.deinit(gpa);
    }

    pub fn count(self: *const Chunk) usize {
        return self._code.items.len;
    }

    pub fn get(self: *const Chunk, offset: usize) u8 {
        return self._code.items[offset];
    }

    pub fn getConstant(self: *const Chunk, constant: usize) Value {
        return self._constants.items[constant];
    }

    pub fn lineOf(self: *const Chunk, offset: usize) usize {
        if (self._lineInfo.items.len == 1) return self._lineInfo.items[0].line;
        for (self._lineInfo.items, 1..) |lineInfo, i| {
            if (offset < lineInfo.offset) {
                return self._lineInfo.items[i - 1].line;
            }
        }
        return self._lineInfo.items[self._lineInfo.items.len - 1].line;
    }

    pub fn write(self: *Chunk, gpa: std.mem.Allocator, byte: u8, line: usize) !void {
        try self._code.append(gpa, byte);
        if (self._lineInfo.items.len == 0 or
            self._lineInfo.items[self._lineInfo.items.len - 1].line != line)
        {
            try self._lineInfo.append(gpa, .{ .offset = self._code.items.len - 1, .line = line });
        }
    }

    pub fn addConstant(self: *Chunk, gpa: std.mem.Allocator, value: Value) !u8 {
        try self._constants.append(gpa, value);
        return @intCast(self._constants.items.len - 1);
    }
};

pub const OpCode = enum {
    CONSTANT,
    RETURN,
};

const Value = f64;

pub fn printValue(value: Value) void {
    std.debug.print("{}", .{value});
}

const LineInfo = struct {
    offset: usize,
    line: usize,
};
