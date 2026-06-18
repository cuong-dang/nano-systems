const std = @import("std");

const Chunk = @import("./chunk.zig").Chunk;
const VM = @import("./vm.zig").VM;

pub const ValueTypeTag = enum { boolean, number, obj, nil };

// Values are owned by VM.
pub const Value = union(ValueTypeTag) {
    boolean: bool,
    number: f64,
    obj: *Obj,
    nil: void,

    pub fn fromIdentifier(vm: *VM, s: []const u8) !Value {
        const obj = try Obj.fromStrings(vm, &[_][]const u8{s});
        vm.addObject(obj);
        return .{ .obj = obj };
    }

    pub fn asBool(self: *const Value) bool {
        return switch (self.*) {
            .nil => false,
            .boolean => |v| v,
            else => true,
        };
    }

    pub fn equals(self: *const Value, b: Value) bool {
        if (@as(ValueTypeTag, self.*) != @as(ValueTypeTag, b)) return false;
        return switch (self.*) {
            .nil => true,
            .boolean => self.boolean == b.boolean,
            .number => self.number == b.number,
            .obj => |v| {
                if (@as(ObjTypeTag, self.obj.data) != @as(ObjTypeTag, b.obj.data)) return false;
                switch (v.data) {
                    .string => return std.mem.eql(u8, self.obj.data.string, b.obj.data.string),
                    .function => return std.mem.eql(u8, self.obj.data.function.name, b.obj.data.function.name),
                    .nativeFn => |nf| return nf == b.obj.data.nativeFn,
                    .closure => unreachable,
                }
            },
        };
    }

    pub fn fmt(self: *const Value, buf: []u8) ![]const u8 {
        return switch (self.*) {
            .boolean => |v| std.fmt.bufPrint(buf, "{}", .{v}),
            .number => |v| std.fmt.bufPrint(buf, "{}", .{v}),
            .obj => |o| switch (o.data) {
                .string => |s| std.fmt.bufPrint(buf, "'{s}'", .{s}),
                .function => |f| std.fmt.bufPrint(buf, "<fn {s}>", .{f.name}),
                .nativeFn => std.fmt.bufPrint(buf, "<native fn>", .{}),
                .closure => |c| std.fmt.bufPrint(buf, "<cfn {s}>", .{c.function.name}),
            },
            .nil => std.fmt.bufPrint(buf, "nil", .{}),
        };
    }
};

pub const ObjTypeTag = enum { string, function, nativeFn, closure };

const ObjData = union(ObjTypeTag) { string: []u8, function: Function, nativeFn: NativeFn, closure: Closure };

// Objects are owned by VM.
pub const Obj = struct {
    data: ObjData,
    next: ?*Obj = null,

    pub fn deinit(self: *Obj, vm: *VM) void {
        switch (self.data) {
            .string => |s| vm.gpa.free(s),
            .function => |*f| {
                f.chunk.deinit(vm.gpa);
                if (f.name.len != 0) {
                    vm.gpa.free(f.name);
                }
            },
            .nativeFn => {},
            .closure => {},
        }
        vm.gpa.destroy(self);
    }

    pub fn fromString(vm: *VM, s: []const u8) !*Obj {
        return try fromStrings(vm, &[_][]const u8{s[1 .. s.len - 1]});
    }

    pub fn fromStrings(vm: *VM, ss: []const []const u8) !*Obj {
        var obj = try vm.gpa.create(Obj);
        vm.addObject(obj);

        var len: usize = 0;
        for (ss) |s| len += s.len;
        obj.* = .{ .data = .{ .string = try vm.gpa.alloc(u8, len) } };

        len = 0;
        for (ss) |s| {
            @memcpy(obj.data.string[len .. len + s.len], s);
            len += s.len;
        }
        return obj;
    }

    pub fn newFunction(vm: *VM) !*Obj {
        const obj = try vm.gpa.create(Obj);
        vm.addObject(obj);
        obj.* = .{ .data = .{ .function = .{ .arity = 0, .name = "", .chunk = .init(vm.gpa) } }, .next = null };
        return obj;
    }

    pub fn newNativeFn(vm: *VM, nativeFn: NativeFn) !*Obj {
        const obj = try vm.gpa.create(Obj);
        vm.addObject(obj);
        obj.* = .{ .data = .{ .nativeFn = nativeFn } };
        return obj;
    }

    pub fn newClosure(vm: *VM, function: *Function) !*Obj {
        const obj = try vm.gpa.create(Obj);
        vm.addObject(obj);
        obj.* = .{ .data = .{ .closure = .{ .function = function } } };
        return obj;
    }
};

pub const Function = struct {
    arity: usize,
    chunk: Chunk,
    name: []u8,
};

pub const NativeFn = *const fn (*VM, usize, [*]Value, *NativeFnError) Value;

pub const NativeFnError = struct {
    ok: bool = true,
    message: ?[]const u8 = null,
};

pub const Closure = struct {
    function: *Function,
};

pub fn printValue(value: Value) void {
    switch (value) {
        .obj => |v| switch (v.data) {
            .string => |s| std.debug.print("'{s}'", .{s}),
            .function => |f| if (f.name.len != 0) std.debug.print("<fn {s}>", .{f.name}) else std.debug.print("<script>", .{}),
            .nativeFn => std.debug.print("<native fn>", .{}),
            .closure => |c| std.debug.print("<cfn {s}>", .{c.function.name}),
        },
        else => |v| std.debug.print("{}", .{v}),
    }
}
