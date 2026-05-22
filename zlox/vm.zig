const std = @import("std");
const builtin = @import("builtin");

const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;
const Value = @import("./chunk.zig").Value;
const Compiler = @import("./compiler.zig").Compiler;
const printValue = @import("./chunk.zig").printValue;
const debug = @import("./debug.zig");

const stackMax = 256;

pub const VM = struct {
    chunk: *Chunk,
    ip: [*]const u8,
    stack: [stackMax]Value,
    stackTop: [*]Value,
    gpa: std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator) VM {
        return .{ .chunk = undefined, .ip = undefined, .stack = undefined, .stackTop = undefined, .gpa = gpa };
    }

    pub fn resetStack(self: *VM) void {
        self.stackTop = &self.stack;
    }

    pub fn interpret(self: *VM, source: []const u8) InterpretResult {
        const chunk: Chunk = .init();
        defer chunk.deinit(self.gpa);
        var compiler: Compiler = .init(source);

        if (!compiler.compile(&chunk)) {
            return .INTERPRET_COMPILE_ERROR;
        }

        self.chunk = &chunk;
        self.ip = chunk.code();

        return run();
    }

    fn run(self: *VM) InterpretResult {
        while (true) {
            if (builtin.mode == .Debug) {
                const count = self.stackTop - &self.stack;
                for (0..count) |i| {
                    std.debug.print("[ ", .{});
                    printValue(self.stack[i]);
                    std.debug.print(" ]", .{});
                }
                if (count != 0) {
                    std.debug.print("\n", .{});
                }

                _ = debug.disassembleInstruction(self.chunk, self.ip - self.chunk.code());
            }

            const instruction: OpCode = @enumFromInt(self.read_byte());
            switch (instruction) {
                .CONSTANT => {
                    const constant = self.read_constant();
                    self.push(constant);
                },
                .ADD => self.push(self.pop() + self.pop()),
                .SUBTRACT => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(a - b);
                },
                .MULTIPLY => self.push(self.pop() * self.pop()),
                .DIVIDE => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(a / b);
                },
                .NEGATE => self.push(-self.pop()),
                .RETURN => {
                    return .INTERPRET_OK;
                },
            }
        }
    }

    fn read_byte(self: *VM) u8 {
        const byte = self.ip[0];
        self.ip += 1;
        return byte;
    }

    fn read_constant(self: *VM) Value {
        return self.chunk.getConstant(self.read_byte());
    }

    fn push(self: *VM, value: Value) void {
        self.stackTop[0] = value;
        self.stackTop += 1;
    }

    fn pop(self: *VM) Value {
        self.stackTop -= 1;
        return self.stackTop[0];
    }
};

const InterpretResult = enum { INTERPRET_OK, INTERPRET_COMPILE_ERROR, INTERPRET_RUNTIME_ERROR };
