const std = @import("std");

pub const Chunk = struct {
    _code: std.ArrayList(u8),
    _constants: std.ArrayList(Value),

    pub fn init() Chunk {
        return .{ ._code = .empty, ._constants = .empty };
    }

    pub fn deinit(self: *Chunk, gpa: std.mem.Allocator) void {
        self._code.deinit(gpa);
        self._constants.deinit(gpa);
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

    pub fn write(self: *Chunk, gpa: std.mem.Allocator, byte: u8) !void {
        try self._code.append(gpa, byte);
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
