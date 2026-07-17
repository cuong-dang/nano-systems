const std = @import("std");

const pageSize = @import("page.zig").size;
const PageId = @import("page.zig").PageId;
const Rid = @import("rid.zig").Rid;

pub const PageType = enum { internal, leaf };

pub fn BasePage(
    comptime Key: type,
    comptime cmp: fn (a: Key, b: Key) i32,
) type {
    return struct {
        const Self = @This();

        pageType: PageType,
        maxSize: usize,
        size: usize = 0,
        pageId: PageId,

        pub fn init(pageType: PageType, maxSize: usize, pageId: PageId) Self {
            return .{ .pageType = pageType, .maxSize = maxSize, .pageId = pageId };
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.size == 0;
        }

        pub fn isFull(self: *const Self) bool {
            return self.size >= self.maxSize;
        }

        pub fn indexOf(self: *const Self, keys: [*]const Key, key: Key) usize {
            const from: usize = if (self.pageType == .internal) 1 else 0;
            std.debug.assert(!self.isEmpty());
            std.debug.assert(!Self.keyLt(key, keys[from]));
            var lo: usize = from;
            var hi = self.size - 1;
            while (lo <= hi) {
                var mid = (lo + hi) / 2;
                if (Self.keyEquals(keys[mid], key)) {
                    while (mid <= hi and Self.keyEquals(keys[mid], key)) {
                        mid += 1;
                    }
                    return mid - 1;
                }
                if (Self.keyLt(keys[mid], key)) {
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

const internalPageHeaderSize = 12;

pub fn InternalPage(
    comptime Key: type,
    comptime cmp: fn (a: Key, b: Key) i32,
    comptime maxSize: ?usize,
) type {
    return struct {
        const Self = @This();
        const slotCount = if (maxSize != null) maxSize.? else (pageSize - internalPageHeaderSize) / (@sizeOf(Key) + @sizeOf(PageId));

        base: BasePage(Key, cmp),
        // One additional slot for splitting.
        keys: [slotCount + 1]Key = undefined,
        vals: [slotCount + 1]PageId = undefined,

        pub fn init(pageId: PageId) Self {
            return .{ .base = .init(.internal, slotCount, pageId) };
        }

        pub fn clone(self: *const Self) Self {
            return self.*;
        }

        pub fn findVal(self: *const Self, val: PageId) ?usize {
            for (0..self.base.size) |i| {
                if (self.vals[i] == val) return i;
            }
            return null;
        }

        pub fn insertAt(self: *Self, i: usize, key: Key, val: PageId) void {
            if (!self.base.isEmpty()) {
                var j = self.base.size - 1;
                while (j >= i) : (j -= 1) {
                    self.keys[j + 1] = self.keys[j];
                    self.vals[j + 1] = self.vals[j];
                    if (j == 0) break;
                }
            }
            self.keys[i] = key;
            self.vals[i] = val;
            self.base.size += 1;
        }

        pub fn fillFrom(self: *Self, src: Self, srcFrom: usize, srcTo: usize) void {
            self.base.size = srcTo - srcFrom;
            for (0..self.base.size) |i| {
                if (i < self.base.size - 1) {
                    self.keys[i + 1] = src.keys[srcFrom + i + 1];
                }
                self.vals[i] = src.vals[srcFrom + i];
            }
        }
    };
}

const leafPageHeaderSize = 16;

pub fn LeafPage(
    comptime Key: type,
    comptime cmp: fn (a: Key, b: Key) i32,
    comptime maxSize: ?usize,
    comptime tombCount: ?usize,
) type {
    return struct {
        const Self = @This();
        const tc = if (tombCount != null) tombCount.? else 0;
        const slotCount = if (maxSize != null) maxSize.? else (pageSize - leafPageHeaderSize - @sizeOf(usize) - (tc * @sizeOf(usize))) / (@sizeOf(Key) + @sizeOf(Rid));
        const BasePage_ = BasePage(Key, cmp);

        base: BasePage_,
        // One additional slot for splitting.
        keys: [slotCount + 1]Key = undefined,
        vals: [slotCount + 1]Rid = undefined,
        nextPageId: ?PageId = null,

        pub fn init(pageId: PageId) Self {
            return .{ .base = .init(.leaf, slotCount, pageId) };
        }

        pub fn insert(self: *Self, key: Key, rid: Rid) void {
            if (self.base.isEmpty() or BasePage_.keyLt(key, self.keys[0])) {
                // Leaf is empty or key K is smallest.
                self.insertAt(0, key, rid);
                return;
            }
            // Else, insert right after highest i such that K_i <= K.
            self.insertAt(self.base.indexOf(&self.keys, key) + 1, key, rid);
        }

        pub fn clone(self: *const Self) Self {
            return self.*;
        }

        fn insertAt(self: *Self, i: usize, key: Key, rid: Rid) void {
            if (!self.base.isEmpty()) {
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

        pub fn fillFrom(self: *Self, src: Self, srcFrom: usize, srcTo: usize) void {
            self.base.size = srcTo - srcFrom;
            for (0..self.base.size) |i| {
                self.keys[i] = src.keys[srcFrom + i];
                self.vals[i] = src.vals[srcFrom + i];
            }
        }
    };
}
