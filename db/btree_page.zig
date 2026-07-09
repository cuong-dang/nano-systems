const std = @import("std");

const pageSize = @import("page.zig").size;
const PageId = @import("page.zig").PageId;
const Rid = @import("rid.zig").Rid;

pub const PageType = enum { internal, leaf };

pub const BasePage = struct {
    pageType: PageType,
    size: usize = 0,
    maxSize: usize,
};

const internalPageHeaderSize = 12;

pub fn InternalPage(comptime Key: type, comptime maxSize: ?usize) type {
    const slotCount = if (maxSize != null) maxSize.? else (pageSize - internalPageHeaderSize) / (@sizeOf(Key) + @sizeOf(PageId));

    return struct {
        const Self = @This();

        base: BasePage = .{ .pageType = .internal, .maxSize = slotCount },
        keys: [slotCount]Key = undefined,
        vals: [slotCount]usize = undefined,

        pub fn keyAt(self: *const Self, index: usize) Key {
            return self.keys[index];
        }

        pub fn setKeyAt(self: *Self, index: usize, key: *const Key) void {
            self.keys[index] = key.*;
        }

        pub fn valueIndex(self: *const Self, value: usize) usize {
            for (self.vals, 0..) |v, i| {
                if (v == value) return i;
            }
        }

        pub fn valueAt(self: *const Self, index: usize) usize {
            return self.vals[index];
        }
    };
}

const leafPageHeaderSize = 16;

pub fn LeafPage(comptime Key: type, comptime maxSize: ?usize, comptime tombCount: usize) type {
    const slotCount = if (maxSize != null) maxSize.? else (pageSize - leafPageHeaderSize - @sizeOf(usize) - (tombCount * @sizeOf(usize))) / (@sizeOf(Key) + @sizeOf(Rid));

    return struct {
        const Self = @This();

        base: BasePage = .{ .pageType = .leaf, .maxSize = slotCount },
        keys: [slotCount]?Key = undefined,
        vals: [slotCount]Rid = undefined,
        nextPageId: ?PageId = null,

        pub fn isEmpty(self: *const Self) bool {
            return self.base.size == 0;
        }

        pub fn isFull(self: *const Self) bool {
            return self.base.size >= self.base.maxSize;
        }

        pub fn insertAt(self: *Self, i: usize, key: Key, rid: Rid) void {
            std.debug.assert(!self.isFull());
            if (!self.isEmpty()) {
                var j = self.base.size - 1;
                while (j >= i) : (j -= 1) {
                    self.keys[j + 1] = self.keys[j];
                    self.vals[j + 1] = self.vals[j];
                }
            }
            self.keys[i] = key;
            self.vals[i] = rid;

            self.base.size += 1;
        }
    };
}
