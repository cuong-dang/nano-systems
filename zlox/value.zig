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

pub fn printValue(value: Value) void {
    switch (value) {
        .obj => |v| switch (v.*) {
            .string => |s| std.debug.print("'{s}'", .{s}),
        },
        else => |v| std.debug.print("{}", .{v}),
    }
}

pub const ObjTypeTag = enum { string };

pub const Obj = union(ObjTypeTag) {
    string: []u8,
};

pub fn makeString(gpa: std.mem.Allocator, s: []const u8) !*Obj {
    var obj = try gpa.create(Obj);
    obj.string = try gpa.dupe(u8, s[1 .. s.len - 1]);
    return obj;
}

pub fn concatStrings(gpa: std.mem.Allocator, s1: []const u8, s2: []const u8) !*Obj {
    var obj = try gpa.create(Obj);
    obj.string = try gpa.alloc(u8, s1.len + s2.len);
    @memcpy(obj.string[0..s1.len], s1);
    @memcpy(obj.string[s1.len..], s2);
    return obj;
}
