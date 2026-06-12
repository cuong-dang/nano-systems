const std = @import("std");
const builtin = @import("builtin");

const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;
const Value = @import("./value.zig").Value;
const Obj = @import("./value.zig").Obj;
const Function = @import("./value.zig").Function;
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
        return .{ .globals = .init(gpa), .gpa = gpa, .io = io };
    }

    pub fn deinit(self: *VM) void {
        // Free objects.
        var obj: ?*Obj = self.objects;
        while (obj != null) {
            const next = obj.?.next;
            obj.?.deinit(self.gpa);
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
        self.push(.{ .obj = functionObj.? });
        self.objects = functionObj.?;
        var frame = &self.frames[self.frameCount];
        self.frameCount += 1;
        frame.function = &functionObj.?.data.function;
        frame.ip = frame.function.chunk.code();
        frame.slots = &self.stack;

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

                _ = debug.disassembleInstruction(&frame.function.chunk, frame.ip - frame.function.chunk.code());
            }

            const instruction: OpCode = @enumFromInt(frame.readByte());
            switch (instruction) {
                .CONSTANT => {
                    const constant = frame.readConstant();
                    self.push(constant);
                },
                .NIL => self.push(.{ .nil = void{} }),
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
                            const obj = Obj.fromStrings(self.gpa, &[_][]const u8{ a.obj.data.string, b.obj.data.string }) catch return self.allocError();
                            self.addObject(obj);
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

        const frame = &self.frames[self.frameCount - 1];
        const instruction = frame.ip - frame.function.chunk.code() - 1;
        const line = frame.function.chunk.lineOf(instruction);
        std.debug.print("[line {}] in script\n", .{line});
        self.resetStack();
    }

    fn allocError(self: *VM) InterpretResult {
        self.runtimeError("Memory allocation error.", .{});
        return .INTERPRET_RUNTIME_ERROR;
    }
};

const InterpretResult = enum { INTERPRET_OK, INTERPRET_COMPILE_ERROR, INTERPRET_RUNTIME_ERROR };

const CallFrame = struct {
    function: *Function,
    ip: [*]const u8,
    slots: [*]Value,

    fn readByte(self: *CallFrame) u8 {
        const byte = self.ip[0];
        self.ip += 1;
        return byte;
    }

    fn readConstant(self: *CallFrame) Value {
        return self.function.chunk.getConstant(self.readByte());
    }

    fn readShort(self: *CallFrame) u16 {
        const short: u16 = (@as(u16, self.ip[0]) << 8) | @as(u16, self.ip[1]);
        self.ip += 2;
        return short;
    }
};
