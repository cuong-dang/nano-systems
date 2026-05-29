const std = @import("std");
const builtin = @import("builtin");

const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;
const Value = @import("./value.zig").Value;
const Obj = @import("./value.zig").Obj;
const ValueTypeTag = @import("./value.zig").ValueTypeTag;
const ObjTypeTag = @import("./value.zig").ObjTypeTag;
const printValue = @import("./value.zig").printValue;
const Compiler = @import("./compiler.zig").Compiler;
const debug = @import("./debug.zig");

const stackMax = 256;

pub const VM = struct {
    chunk: *Chunk,
    ip: [*]const u8,
    stack: [stackMax]Value,
    stackTop: [*]Value,
    objects: ?*Obj,
    gpa: std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator) VM {
        return .{ .chunk = undefined, .ip = undefined, .stack = undefined, .stackTop = undefined, .objects = null, .gpa = gpa };
    }

    pub fn deinit(self: *VM) void {
        self.chunk.deinit(self.gpa);
        self.gpa.destroy(self.chunk);
        // Free objects.
        var obj: ?*Obj = self.objects;
        while (obj != null) {
            const next = obj.?.next;
            // Free object.
            switch (obj.?.data) {
                .string => |s| self.gpa.free(s),
            }
            self.gpa.destroy(obj.?);
            obj = next;
        }
    }

    pub fn interpret(self: *VM, source: []const u8) InterpretResult {
        self.chunk = self.gpa.create(Chunk) catch return .INTERPRET_RUNTIME_ERROR;
        self.chunk.* = Chunk.init(self.gpa);

        self.resetStack();

        if (!(Compiler.compile(self.gpa, source, self))) {
            return .INTERPRET_COMPILE_ERROR;
        }

        self.ip = self.chunk.code();

        return self.run();
    }

    fn run(self: *VM) InterpretResult {
        if (builtin.mode == .Debug) {
            std.debug.print("== run ==\n", .{});
        }
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
                .NIL => self.push(.{ .nil = void{} }),
                .TRUE => self.push(.{ .boolean = true }),
                .FALSE => self.push(.{ .boolean = false }),
                .EQUAL => self.push(.{ .boolean = self.pop().equals(self.pop()) }),
                .GREATER => {
                    if (!self.ensure2Numbers()) {
                        self.runtimeError("Operands must be numbers.", .{});
                        return .INTERPRET_RUNTIME_ERROR;
                    }
                    self.push(.{ .boolean = self.pop().number < self.pop().number });
                },
                .LESS => {
                    if (!self.ensure2Numbers()) {
                        self.runtimeError("Operands must be numbers.", .{});
                        return .INTERPRET_RUNTIME_ERROR;
                    }
                    self.push(.{ .boolean = self.pop().number > self.pop().number });
                },
                .ADD => {
                    if (!(self.ensure2Numbers() or self.ensure2Strings())) {
                        self.runtimeError("Operands must be two numbers or two strings.", .{});
                        return .INTERPRET_RUNTIME_ERROR;
                    }
                    const b = self.pop();
                    const a = self.pop();
                    switch (a) {
                        .number => self.push(.{ .number = a.number + b.number }),
                        .obj => {
                            const obj = Obj.fromStrings(self.gpa, &[_][]const u8{ a.obj.data.string, b.obj.data.string }, self) catch return .INTERPRET_RUNTIME_ERROR;
                            self.push(.{ .obj = obj });
                        },
                        else => unreachable,
                    }
                },
                .SUBTRACT => {
                    if (!self.ensure2Numbers()) {
                        self.runtimeError("Operands must be numbers.", .{});
                        return .INTERPRET_RUNTIME_ERROR;
                    }
                    const b = self.pop().number;
                    const a = self.pop().number;
                    self.push(.{ .number = a - b });
                },
                .MULTIPLY => {
                    if (!self.ensure2Numbers()) {
                        self.runtimeError("Operands must be numbers.", .{});
                        return .INTERPRET_RUNTIME_ERROR;
                    }
                    self.push(.{ .number = self.pop().number * self.pop().number });
                },
                .DIVIDE => {
                    if (!self.ensure2Numbers()) {
                        self.runtimeError("Operands must be numbers.", .{});
                        return .INTERPRET_RUNTIME_ERROR;
                    }
                    const b = self.pop().number;
                    const a = self.pop().number;
                    self.push(.{ .number = a / b });
                },
                .NOT => {
                    if (!self.ensureBoolish()) {
                        self.runtimeError("Operand must be a bool or nil.", .{});
                        return .INTERPRET_RUNTIME_ERROR;
                    }
                    self.push(.{ .boolean = !self.pop().asBool() });
                },
                .NEGATE => {
                    if (!self.ensureNumber()) {
                        self.runtimeError("Operand must be a number.", .{});
                        return .INTERPRET_RUNTIME_ERROR;
                    }
                    self.push(.{ .number = -self.pop().number });
                },
                .RETURN => {
                    return .INTERPRET_OK;
                },
            }
        }
    }

    pub fn addObject(self: *VM, obj: *Obj) void {
        obj.next = self.objects;
        self.objects = obj;
    }

    fn read_byte(self: *VM) u8 {
        const byte = self.ip[0];
        self.ip += 1;
        return byte;
    }

    fn read_constant(self: *VM) Value {
        return self.chunk.getConstant(self.read_byte());
    }

    fn push(self: *VM, v: Value) void {
        self.stackTop[0] = v;
        self.stackTop += 1;
    }

    fn pop(self: *VM) Value {
        self.stackTop -= 1;
        return self.stackTop[0];
    }

    fn peek(self: *const VM, distance: usize) Value {
        return (self.stackTop - 1 - distance)[0];
    }

    fn ensureNumber(self: *const VM) bool {
        return self.ensureValueType(0, ValueTypeTag.number);
    }

    fn ensure2Numbers(self: *const VM) bool {
        return self.ensureValueType(0, ValueTypeTag.number) and self.ensureValueType(1, ValueTypeTag.number);
    }

    fn ensure2Strings(self: *const VM) bool {
        return self.ensureObjType(0, ObjTypeTag.string) and self.ensureObjType(1, ObjTypeTag.string);
    }

    fn ensureBoolish(self: *const VM) bool {
        return self.ensureValueType(0, ValueTypeTag.boolean) or self.ensureValueType(0, ValueTypeTag.nil);
    }

    fn ensureValueType(self: *const VM, distance: usize, tag: ValueTypeTag) bool {
        return @as(ValueTypeTag, self.peek(distance)) == tag;
    }

    fn ensureObjType(self: *const VM, distance: usize, tag: ObjTypeTag) bool {
        return self.ensureValueType(distance, ValueTypeTag.obj) and @as(ObjTypeTag, self.peek(distance).obj.data) == tag;
    }

    fn resetStack(self: *VM) void {
        self.stackTop = &self.stack;
    }

    fn runtimeError(self: *VM, comptime format: []const u8, args: anytype) void {
        std.debug.print(format, args);
        std.debug.print("\n", .{});

        const instruction = self.ip - self.chunk.code() - 1;
        const line = self.chunk.lineOf(instruction);
        std.debug.print("[line {}] in script\n", .{line});
        self.resetStack();
    }
};

const InterpretResult = enum { INTERPRET_OK, INTERPRET_COMPILE_ERROR, INTERPRET_RUNTIME_ERROR };
