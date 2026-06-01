const std = @import("std");

const VM = @import("./vm.zig").VM;

pub const ValueTypeTag = enum { boolean, number, obj, nil };

pub const Value = union(ValueTypeTag) {
    boolean: bool,
    number: f64,
    obj: *Obj,
    nil: void,

    pub fn asBool(self: *const Value) bool {
        return switch (self.*) {
            .nil => false,
            .boolean => |v| v,
            else => unreachable,
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
            },
            .nil => std.fmt.bufPrint(buf, "nil", .{}),
        };
    }
};

pub const ObjTypeTag = enum { string };

const ObjData = union(ObjTypeTag) { string: []u8 };

pub const Obj = struct {
    data: ObjData,
    next: ?*Obj,

    pub fn deinit(self: *Obj, gpa: std.mem.Allocator) void {
        switch (self.data) {
            .string => |s| gpa.free(s),
        }
        gpa.destroy(self);
    }

    pub fn fromString(gpa: std.mem.Allocator, s: []const u8, vm: *VM) !*Obj {
        return try fromStrings(gpa, &[_][]const u8{s[1 .. s.len - 1]}, vm);
    }

    pub fn fromStrings(gpa: std.mem.Allocator, ss: []const []const u8, vm: *VM) !*Obj {
        var obj = try gpa.create(Obj);

        var len: usize = 0;
        for (ss) |s| len += s.len;
        obj.data.string = try gpa.alloc(u8, len);

        len = 0;
        for (ss) |s| {
            @memcpy(obj.data.string[len .. len + s.len], s);
            len += s.len;
        }

        vm.addObject(obj);
        return obj;
    }
};

pub fn printValue(value: Value) void {
    switch (value) {
        .obj => |v| switch (v.data) {
            .string => |s| std.debug.print("'{s}'", .{s}),
        },
        else => |v| std.debug.print("{}", .{v}),
    }
}
