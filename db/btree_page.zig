const pageSize = @import("page.zig").size;

const PageType = enum { internal, leaf };

const BasePage = struct {
    pageType: PageType,
    size: usize,
    maxSize: usize,
};

const internalPageHeaderSize = 12;

pub fn InternalPage(comptime K: type) type {
    const slotCount = (pageSize - internalPageHeaderSize) / (@sizeOf(K) + @sizeOf(usize));

    return struct {
        base: BasePage = .{
            .pageType = .internal,
            .size = 0,
            .maxSize = slotCount,
        },
        keys: [slotCount]K = undefined,
        vals: [slotCount]usize = undefined,

        pub fn keyAt(self: *const InternalPage(K), index: usize) K {
            return self.keys[index];
        }

        pub fn setKeyAt(self: *InternalPage(K), index: usize, key: *const K) void {
            self.keys[index] = key.*;
        }

        pub fn valueIndex(self: *const InternalPage(K), value: usize) usize {
            for (self.vals, 0..) |v, i| {
                if (v == value) return i;
            }
        }

        pub fn valueAt(self: *const InternalPage(K), index: usize) usize {
            return self.vals[index];
        }
    };
}
