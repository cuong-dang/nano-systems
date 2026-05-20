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
    _chunk: *Chunk,
    _ip: [*]const u8,
    _stack: [stackMax]Value,
    _stackTop: [*]Value,

    pub fn init() VM {
        return .{ ._chunk = undefined, ._ip = undefined, ._stack = undefined, ._stackTop = undefined };
    }

    pub fn resetStack(self: *VM) void {
        self._stackTop = &self._stack;
    }

    pub fn interpret(source: []const u8) InterpretResult {
        Compiler.compile(source);
        return .INTERPRET_OK;
    }

    fn run(self: *VM) InterpretResult {
        while (true) {
            if (builtin.mode == .Debug) {
                const count = self._stackTop - &self._stack;
                for (0..count) |i| {
                    std.debug.print("[ ", .{});
                    printValue(self._stack[i]);
                    std.debug.print(" ]", .{});
                }
                if (count != 0) {
                    std.debug.print("\n", .{});
                }

                _ = debug.disassembleInstruction(self._chunk, self._ip - self._chunk.code());
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
        const byte = self._ip[0];
        self._ip += 1;
        return byte;
    }

    fn read_constant(self: *VM) Value {
        return self._chunk.getConstant(self.read_byte());
    }

    fn push(self: *VM, value: Value) void {
        self._stackTop[0] = value;
        self._stackTop += 1;
    }

    fn pop(self: *VM) Value {
        self._stackTop -= 1;
        return self._stackTop[0];
    }
};

const InterpretResult = enum { INTERPRET_OK, INTERPRET_COMPILE_ERROR, INTERPRET_RUNTIME_ERROR };
