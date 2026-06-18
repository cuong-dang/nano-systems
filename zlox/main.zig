const std = @import("std");

const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;
const debug = @import("./debug.zig");
const VM = @import("./vm.zig").VM;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.gpa);
    var vm: VM = .init(init.gpa, init.io);
    defer vm.deinit();

    if (args.len == 1) {
        try repl(init.io, &vm);
    } else if (args.len == 2) {
        try runFile(init.gpa, init.io, &vm, args[1]);
    } else {
        std.debug.print("Usage: zlox [path]\n", .{});
        std.process.exit(64);
    }
}

fn repl(io: std.Io, vm: *VM) !void {
    var buffer: [1024]u8 = undefined;
    var reader = std.Io.File.stdin().reader(io, &buffer);

    while (true) {
        try std.Io.File.stdout().writeStreamingAll(io, "> ");
        if (try reader.interface.takeDelimiter('\n')) |line| {
            _ = vm.interpret(line);
        }
    }
}

fn runFile(gpa: std.mem.Allocator, io: std.Io, vm: *VM, path: []const u8) !void {
    _ = vm.interpret(try std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), io, path, gpa, .unlimited));
}
