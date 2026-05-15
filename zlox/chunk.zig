const std = @import("std");

pub const OpCode = enum {
    RETURN,
};

pub const Chunk = struct {
    _code: std.ArrayList(u8),

    pub fn init() Chunk {
        return .{ ._code = .empty };
    }

    pub fn deinit(self: *Chunk, gpa: std.mem.Allocator) void {
        self._code.deinit(gpa);
    }

    pub fn count(self: *const Chunk) usize {
        return self._code.items.len;
    }

    pub fn get(self: *const Chunk, offset: usize) u8 {
        return self._code.items[offset];
    }

    pub fn write(self: *Chunk, gpa: std.mem.Allocator, byte: u8) !void {
        try self._code.append(gpa, byte);
    }
};
