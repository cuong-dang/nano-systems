const std = @import("std");

const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;
const debug = @import("./debug.zig");
const VM = @import("./vm.zig").VM;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.gpa);
    var vm: VM = .init(init.gpa);
    defer vm.deinit();

    if (args.len == 1) {
        try repl(&vm, init.io);
        // } else if (args.len == 2) {
        //     runFile(args[1]);
    } else {
        std.debug.print("Usage: zlox [path]\n", .{});
        std.process.exit(64);
    }
}

fn repl(vm: *VM, io: std.Io) !void {
    var buffer: [1024]u8 = undefined;
    var reader = std.Io.File.stdin().reader(io, &buffer);
    var stdin = &reader.interface;

    while (true) {
        try std.Io.File.stdout().writeStreamingAll(io, "> ");
        if (try stdin.takeDelimiter('\n')) |line| {
            _ = vm.interpret(line);
        }
    }
}
