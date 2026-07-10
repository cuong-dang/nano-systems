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

pub fn InternalPage(
    comptime Key: type,
    comptime maxSize: ?usize,
) type {
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

pub fn LeafPage(
    comptime Key: type,
    comptime cmp: fn (a: Key, b: Key) i32,
    comptime maxSize: ?usize,
    comptime tombCount: usize,
) type {
    const slotCount = if (maxSize != null) maxSize.? else (pageSize - leafPageHeaderSize - @sizeOf(usize) - (tombCount * @sizeOf(usize))) / (@sizeOf(Key) + @sizeOf(Rid));

    return struct {
        const Self = @This();

        base: BasePage = .{ .pageType = .leaf, .maxSize = slotCount },
        keys: [slotCount]Key = undefined,
        vals: [slotCount]Rid = undefined,
        nextPageId: ?PageId = null,

        pub fn isEmpty(self: *const Self) bool {
            return self.base.size == 0;
        }

        pub fn isFull(self: *const Self) bool {
            return self.base.size >= self.base.maxSize;
        }

        pub fn insert(self: *Self, key: Key, rid: Rid) void {
            if (self.isEmpty() or Self.keyLt(key, self.keys[0])) {
                // Leaf is empty or key K is smallest.
                self.insertAt(0, key, rid);
                return;
            }
            // Else, insert right after highest i such that K_i <= K.
            self.insertAt(self.findLastLe(key) + 1, key, rid);
        }

        fn insertAt(self: *Self, i: usize, key: Key, rid: Rid) void {
            std.debug.assert(!self.isFull());
            if (!self.isEmpty()) {
                var j = self.base.size - 1;
                while (j >= i) : (j -= 1) {
                    self.keys[j + 1] = self.keys[j];
                    self.vals[j + 1] = self.vals[j];
                    if (j == 0) break;
                }
            }
            self.keys[i] = key;
            self.vals[i] = rid;

            self.base.size += 1;
        }

        fn findLastLe(self: *const Self, key: Key) usize {
            std.debug.assert(!self.isEmpty());
            std.debug.assert(!Self.keyLt(key, self.keys[0]));
            var lo: usize = 0;
            var hi = self.base.size - 1;
            while (lo <= hi) {
                var mid = (lo + hi) / 2;
                if (Self.keyEquals(self.keys[mid], key)) {
                    while (mid <= hi and Self.keyEquals(self.keys[mid], key)) {
                        mid += 1;
                    }
                    return mid - 1;
                }
                if (Self.keyLt(self.keys[mid], key)) {
                    lo = mid + 1;
                } else {
                    // hi should never be 0 because of the 2nd invariant.
                    hi = mid - 1;
                }
            }
            return hi;
        }

        fn keyLt(a: Key, b: Key) bool {
            return cmp(a, b) < 0;
        }

        fn keyEquals(a: Key, b: Key) bool {
            return cmp(a, b) == 0;
        }
    };
}
