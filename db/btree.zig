const std = @import("std");

const PageId = @import("page.zig").PageId;
const WritePage = @import("buffer_pool_manager.zig").WritePage;
const InternalPage_ = @import("btree_page.zig").InternalPage;
const LeafPage_ = @import("btree_page.zig").LeafPage;
const BufferPoolManager = @import("buffer_pool_manager.zig").BufferPoolManager;
const Rid = @import("rid.zig").Rid;

pub fn Btree(
    comptime Key: type,
    comptime cmp: fn (lsh: Key, rhs: Key) i32,
    comptime leafMaxSize: ?usize,
    comptime internalMaxSize: ?usize,
    comptime numTombs: usize,
) type {
    const InternalPage = InternalPage_(Key, internalMaxSize);
    _ = InternalPage;
    const LeafPage = LeafPage_(Key, leafMaxSize, numTombs);

    return struct {
        const Self = @This();

        gpa: std.mem.Allocator,

        name: []const u8,
        headerPageId: PageId,
        bpm: *BufferPoolManager,

        rootPageId: ?PageId = null,

        pub fn init(
            gpa: std.mem.Allocator,
            name: []const u8,
            headerPageId: PageId,
            bpm: *BufferPoolManager,
        ) Self {
            return .{ .gpa = gpa, .name = name, .headerPageId = headerPageId, .bpm = bpm };
        }

        pub fn insert(self: *Self, key: Key, rid: Rid) !void {
            var L: *LeafPage = undefined;
            var page: WritePage = undefined;

            if (self.rootPageId == null) {
                // New leaf page
                self.rootPageId = self.bpm.newPage();
                if (try self.bpm.getWritePage(self.rootPageId.?)) |p| {
                    page = p;
                    L = @ptrCast(@alignCast(page.getDataMut().ptr));
                    L.* = .{};
                } else {
                    return;
                }
            }

            if (!L.isFull()) {
                Self.insertInLeaf(L, key, rid);
            }

            try page.drop();
        }

        fn insertInLeaf(L: *LeafPage, key: Key, rid: Rid) void {
            if (L.isEmpty() or Self.keyLt(key, L.keys[0].?)) {
                L.insertAt(0, key, rid);
                return;
            }
        }

        fn keyLt(k1: Key, k2: Key) bool {
            return cmp(k1, k2) < 0;
        }
    };
}
