const std = @import("std");
const builtin = @import("builtin");

const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;
const Value = @import("./value.zig").Value;
const Obj = @import("./value.zig").Obj;
const Function = @import("./value.zig").Function;
const Closure = @import("value.zig").Closure;
const NativeFn = @import("./value.zig").NativeFn;
const NativeFnError = @import("./value.zig").NativeFnError;
const ValueTypeTag = @import("./value.zig").ValueTypeTag;
const ObjTypeTag = @import("./value.zig").ObjTypeTag;
const printValue = @import("./value.zig").printValue;
const Compiler = @import("./compiler.zig").Compiler;
const debug = @import("./debug.zig");

const FRAMES_MAX = 64;
const STACK_MAX = FRAMES_MAX * std.math.maxInt(u8);

pub const VM = struct {
    frames: [FRAMES_MAX]CallFrame = undefined,
    frameCount: usize = 0,
    stack: [STACK_MAX]Value = undefined,
    stackTop: [*]Value = undefined,
    objects: ?*Obj = null,
    globals: std.StringHashMap(Value),
    gpa: std.mem.Allocator,
    io: std.Io,

    pub fn init(gpa: std.mem.Allocator, io: std.Io) VM {
        var vm: VM = .{ .globals = .init(gpa), .gpa = gpa, .io = io };
        vm.resetStack();
        vm.defineNative("clock", clockNative) catch unreachable; // sloppy
        vm.defineNative("strlen", strlenNative) catch unreachable; // sloppy
        return vm;
    }

    pub fn deinit(self: *VM) void {
        // Free objects.
        var obj: ?*Obj = self.objects;
        while (obj) |o| {
            const next = o.next;
            o.deinit(self);
            obj = next;
        }
        self.globals.deinit();
    }

    pub fn interpret(self: *VM, source: []const u8) InterpretResult {
        self.resetStack();
        const compiler = Compiler.init(self.gpa, self, .SCRIPT, null, null) catch {
            return .INTERPRET_COMPILE_ERROR;
        };
        defer compiler.deinit(true);

        const functionObj = compiler.compile(source);

        if (functionObj == null) {
            return .INTERPRET_COMPILE_ERROR;
        }
        self.objects = functionObj.?;
        self.push(.{ .obj = functionObj.? });
        const closureObj = Obj.newClosure(self, &functionObj.?.data.function) catch return self.allocError();
        _ = self.pop();
        self.push(.{ .obj = closureObj });
        _ = self.call(&closureObj.data.closure, 0);

        return self.run();
    }

    fn run(self: *VM) InterpretResult {
        var frame = &self.frames[self.frameCount - 1];

        if (builtin.mode == .Debug) {
            std.debug.print("== run ==\n", .{});
        }
        while (true) {
            // Print stack.
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

                _ = debug.disassembleInstruction(&frame.closure.function.chunk, frame.ip - frame.closure.function.chunk.code());
            }

            const instruction: OpCode = @enumFromInt(frame.readByte());
            switch (instruction) {
                .CONSTANT => {
                    const constant = frame.readConstant();
                    self.push(constant);
                },
                .NIL => self.push(.{ .nil = {} }),
                .TRUE => self.push(.{ .boolean = true }),
                .FALSE => self.push(.{ .boolean = false }),
                .POP => _ = self.pop(),
                .GET_LOCAL => {
                    self.push(frame.slots[frame.readByte()]);
                },
                .SET_LOCAL => {
                    const slot = frame.readByte();
                    frame.slots[slot] = self.peek(0);
                },
                .GET_GLOBAL => {
                    const name = frame.readConstant().obj.data.string;
                    const value = self.globals.get(name) orelse {
                        self.runtimeError("Undefined variable '{s}'.", .{name});
                        return .INTERPRET_RUNTIME_ERROR;
                    };
                    self.push(value);
                },
                .SET_GLOBAL => {
                    const name = frame.readConstant().obj.data.string;
                    _ = self.globals.get(name) orelse {
                        self.runtimeError("Undefined variable '{s}'.", .{name});
                        return .INTERPRET_RUNTIME_ERROR;
                    };
                    self.globals.put(name, self.peek(0)) catch return self.allocError();
                },
                .DEFINE_GLOBAL => {
                    self.globals.put(frame.readConstant().obj.data.string, self.peek(0)) catch return self.allocError();
                    _ = self.pop();
                },
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
                            const obj = Obj.fromStrings(self, &[_][]const u8{ a.obj.data.string, b.obj.data.string }) catch return self.allocError();
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
                .PRINT => {
                    var buf: [256]u8 = undefined;
                    const s = self.pop().fmt(&buf) catch return self.allocError();
                    std.Io.File.stdout().writeStreamingAll(self.io, s) catch return self.allocError();
                    std.Io.File.stdout().writeStreamingAll(self.io, "\n") catch return self.allocError();
                },
                .JUMP => {
                    const offset = frame.readShort();
                    frame.ip += offset;
                },
                .JUMP_IF_FALSE => {
                    const offset = frame.readShort();
                    if (!self.peek(0).asBool()) frame.ip += offset;
                },
                .LOOP => {
                    const offset = frame.readShort();
                    frame.ip -= offset;
                },
                .CALL => {
                    const argCount = frame.readByte();
                    if (!self.callValue(self.peek(argCount), argCount)) {
                        return .INTERPRET_RUNTIME_ERROR;
                    }
                    frame = &self.frames[self.frameCount - 1];
                },
                .CLOSURE => {
                    const function = &frame.readConstant().obj.data.function;
                    const closure = Obj.newClosure(self, function) catch return self.allocError();
                    self.push(.{ .obj = closure });
                },
                .RETURN => {
                    const result = self.pop();
                    self.frameCount -= 1;
                    if (self.frameCount == 0) {
                        _ = self.pop();
                        return .INTERPRET_OK;
                    }

                    self.stackTop = frame.slots;
                    self.push(result);
                    frame = &self.frames[self.frameCount - 1];
                },
            }
        }
    }

    pub fn addObject(self: *VM, obj: *Obj) void {
        obj.next = self.objects;
        self.objects = obj;
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

    fn callValue(self: *VM, callee: Value, argCount: usize) bool {
        switch (callee) {
            .obj => |o| switch (o.data) {
                .closure => |*c| return self.call(c, argCount),
                .nativeFn => |nf| {
                    var err: NativeFnError = .{};
                    const result = nf(self, argCount, self.stackTop - argCount, &err);
                    if (!err.ok) {
                        self.runtimeError("<native fn>: {s}", .{err.message.?});
                        return false;
                    }
                    self.stackTop -= argCount + 1;
                    self.push(result);
                    return true;
                },
                else => {},
            },
            else => {},
        }
        self.runtimeError("Can only call function and classes.", .{});
        return false;
    }

    fn call(self: *VM, closure: *Closure, argCount: usize) bool {
        if (argCount != closure.function.arity) {
            self.runtimeError("Expected {} arguments but got {}.", .{ closure.function.arity, argCount });
            return false;
        }

        if (self.frameCount == FRAMES_MAX) {
            self.runtimeError("Stack overflow.", .{});
            return false;
        }

        var frame = &self.frames[self.frameCount];
        self.frameCount += 1;
        frame.closure = closure;
        frame.ip = closure.function.chunk.code();
        frame.slots = self.stackTop - argCount - 1;
        return true;
    }

    fn defineNative(self: *VM, name: []const u8, nativeFn: NativeFn) !void {
        self.push(.{ .obj = try Obj.fromString(self, name) });
        self.push(.{ .obj = try Obj.newNativeFn(self, nativeFn) });
        try self.globals.put(name, self.stack[1]);
        _ = self.pop();
        _ = self.pop();
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
        self.frameCount = 0;
    }

    fn runtimeError(self: *VM, comptime format: []const u8, args: anytype) void {
        std.debug.print(format, args);
        std.debug.print("\n", .{});

        var i: usize = self.frameCount - 1;
        while (true) : (i -= 1) {
            const frame = &self.frames[i];
            const function = frame.closure.function;
            const intrusction = frame.ip - function.chunk.code() - 1;
            std.debug.print("[line {}] in ", .{function.chunk.lineOf(intrusction)});
            if (function.name.len == 0) {
                std.debug.print("script\n", .{});
            } else {
                std.debug.print("{s}()\n", .{function.name});
            }
            if (i == 0) break;
        }

        self.resetStack();
    }

    fn allocError(self: *VM) InterpretResult {
        self.runtimeError("Memory allocation error.", .{});
        return .INTERPRET_RUNTIME_ERROR;
    }
};

const InterpretResult = enum { INTERPRET_OK, INTERPRET_COMPILE_ERROR, INTERPRET_RUNTIME_ERROR };

const CallFrame = struct {
    closure: *Closure,
    ip: [*]const u8,
    slots: [*]Value,

    fn readByte(self: *CallFrame) u8 {
        const byte = self.ip[0];
        self.ip += 1;
        return byte;
    }

    fn readConstant(self: *CallFrame) Value {
        return self.closure.function.chunk.getConstant(self.readByte());
    }

    fn readShort(self: *CallFrame) u16 {
        const short: u16 = (@as(u16, self.ip[0]) << 8) | @as(u16, self.ip[1]);
        self.ip += 2;
        return short;
    }
};

fn strlenNative(vm: *VM, argCount: usize, args: [*]Value, err: *NativeFnError) Value {
    _ = vm;
    if (argCount == 1 and args[0] == .obj and args[0].obj.data == .string) {
        return .{ .number = @floatFromInt(args[0].obj.data.string.len) };
    }
    err.* = .{ .ok = false, .message = "strlen expects 1 string argument." };
    return .{ .nil = {} };
}

fn clockNative(vm: *VM, argCount: usize, args: [*]Value, err: *NativeFnError) Value {
    _ = args;
    if (argCount == 0) {
        return .{ .number = @as(f64, @floatFromInt(std.Io.Clock.real.now(vm.io).nanoseconds)) / 1000000000 };
    }
    err.* = .{ .ok = false, .message = "clock expects no arguments." };
    return .{ .nil = {} };
}
