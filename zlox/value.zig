const std = @import("std");

pub const ValueTypeTag = enum { boolean, number, obj, nil };

pub const Value = union(ValueTypeTag) {
    boolean: bool,
    number: f64,
    obj: *Obj,
    nil: void,

    pub fn asBool(self: Value) bool {
        return switch (self) {
            .nil => false,
            .boolean => |v| v,
            else => unreachable,
        };
    }

    pub fn equals(self: Value, b: Value) bool {
        if (@as(ValueTypeTag, self) != @as(ValueTypeTag, b)) return false;
        return switch (self) {
            .nil => true,
            .boolean => self.boolean == b.boolean,
            .number => self.number == b.number,
            .obj => |v| {
                if (@as(ObjTypeTag, self.obj.*) != @as(ObjTypeTag, b.obj.*)) return false;
                switch (v.*) {
                    .string => return std.mem.eql(u8, self.obj.string, b.obj.string),
                }
            },
        };
    }
};

pub const ObjTypeTag = enum { string };

pub const Obj = union(ObjTypeTag) {
    string: []u8,

    pub fn fromString(gpa: std.mem.Allocator, s: []const u8) !*Obj {
        var obj = try gpa.create(Obj);
        obj.string = try gpa.dupe(u8, s[1 .. s.len - 1]);
        return obj;
    }

    pub fn fromStrings(gpa: std.mem.Allocator, ss: []const []const u8) !*Obj {
        var obj = try gpa.create(Obj);

        var len: usize = 0;
        for (ss) |s| len += s.len;
        obj.string = try gpa.alloc(u8, len);

        len = 0;
        for (ss) |s| {
            @memcpy(obj.string[len .. len + s.len], s);
            len += s.len;
        }
        return obj;
    }
};

pub fn printValue(value: Value) void {
    switch (value) {
        .obj => |v| switch (v.*) {
            .string => |s| std.debug.print("'{s}'", .{s}),
        },
        else => |v| std.debug.print("{}", .{v}),
    }
}
