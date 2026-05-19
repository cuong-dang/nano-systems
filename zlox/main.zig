const std = @import("std");

const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;
const debug = @import("./debug.zig");
const VM = @import("./vm.zig").VM;

const gpa = std.heap.page_allocator;

pub fn main() !void {
    var chunk: Chunk = .init();
    defer chunk.deinit(gpa);

    var constant = try chunk.addConstant(gpa, 1);
    try chunk.write(gpa, @intFromEnum(OpCode.CONSTANT), 100);
    try chunk.write(gpa, constant, 100);

    constant = try chunk.addConstant(gpa, 2);
    try chunk.write(gpa, @intFromEnum(OpCode.CONSTANT), 100);
    try chunk.write(gpa, constant, 100);

    try chunk.write(gpa, @intFromEnum(OpCode.SUBTRACT), 100);

    try chunk.write(gpa, @intFromEnum(OpCode.NEGATE), 100);
    try chunk.write(gpa, @intFromEnum(OpCode.RETURN), 100);

    var vm: VM = .init();
    vm.resetStack();
    _ = vm.interpret(&chunk);
}
