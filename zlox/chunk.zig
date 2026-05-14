const std = @import("std");

const OpCode = enum {
    @"return",
};

const Chunk = struct {
    code: std.ArrayList(u8),

    pub fn init() Chunk {
        return .{ .code = .empty };
    }

    pub fn deinit(self: Chunk, gpa: std.mem.Allocator) void {
        self.code.deinit(gpa);
    }

    pub fn write(self: Chunk, )
};
