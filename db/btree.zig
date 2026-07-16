const std = @import("std");

const PageId = @import("page.zig").PageId;
const WritePage = @import("buffer_pool_manager.zig").WritePage;
const BasePage_ = @import("btree_page.zig").BasePage;
const InternalPage_ = @import("btree_page.zig").InternalPage;
const LeafPage_ = @import("btree_page.zig").LeafPage;
const BufferPoolManager = @import("buffer_pool_manager.zig").BufferPoolManager;
const Rid = @import("rid.zig").Rid;

pub fn Btree(
    comptime Key: type,
    comptime cmp: fn (lsh: Key, rhs: Key) i32,
    comptime maxLeafSize: ?usize,
    comptime maxInternalSize: ?usize,
    comptime tombCount: ?usize,
) type {
    const BasePage = BasePage_(Key, cmp);
    const InternalPage = InternalPage_(Key, cmp, maxInternalSize);
    const LeafPage = LeafPage_(Key, cmp, maxLeafSize, tombCount);

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
            var leaf: *LeafPage = undefined;
            var page: WritePage = undefined;
            defer page.drop() catch {};

            if (self.rootPageId == null) {
                // Tree is empty. Create a new leaf page.
                self.rootPageId = self.bpm.newPage();
                if (try self.bpm.getWritePage(self.rootPageId.?)) |wp| {
                    page = wp;
                    leaf = @ptrCast(@alignCast(page.getDataMut().ptr));
                    leaf.* = .{}; // reset
                    leaf.base.pageId = self.rootPageId.?;
                } else {
                    return;
                }
            } else {
                // Find the leaf node that should contain key K.
                var searchPageId = self.rootPageId.?;
                while (true) {
                    var wp = (try self.bpm.getWritePage(searchPageId)).?;
                    const bp: *const BasePage = @ptrCast(@alignCast(wp.getData().ptr));

                    switch (bp.pageType) {
                        .leaf => {
                            page = wp;
                            leaf = @ptrCast(@alignCast(page.getDataMut().ptr));
                            break;
                        },
                        .internal => {
                            const ip: *const InternalPage = @ptrCast(@alignCast(wp.getData().ptr));
                            searchPageId = ip.vals[bp.findLastLe(&ip.keys, key)];
                            try wp.drop();
                        },
                    }
                }
            }

            if (!leaf.base.isFull()) {
                leaf.insert(key, rid);
            } else {
                // Split the leaf.
                const newPageId = self.bpm.newPage();
                if (try self.bpm.getWritePage(newPageId)) |wp| {
                    var newPage = wp;
                    defer newPage.drop() catch {};
                    var newLeaf: *LeafPage = @ptrCast(@alignCast(newPage.getDataMut().ptr));
                    newLeaf.* = .{};
                    newLeaf.base.pageId = newPageId;
                    var tmpLeaf: LeafPage = leaf.clone();
                    // Insert into the temp leaf.
                    tmpLeaf.insert(key, rid);
                    // Wire new leaf into list.
                    newLeaf.nextPageId = leaf.nextPageId;
                    leaf.nextPageId = newPageId;
                    // Copy keys and values.
                    leaf.fillFrom(tmpLeaf, 0, tmpLeaf.base.size / 2);
                    newLeaf.fillFrom(tmpLeaf, tmpLeaf.base.size / 2, tmpLeaf.base.size);
                    // Insert in parent.
                    try self.insertInParent(leaf, newLeaf.keys[0], newLeaf);
                }
            }
        }

        fn insertInParent(self: *Self, leaf: *LeafPage, key: Key, newLeaf: *LeafPage) !void {
            // Root page.
            if (leaf.base.pageId == self.rootPageId) {
                const newRootPageId = self.bpm.newPage();
                if (try self.bpm.getWritePage(newRootPageId)) |wp| {
                    var p = wp;
                    defer p.drop() catch {};
                    var ip: *InternalPage = @ptrCast(@alignCast(p.getDataMut().ptr));
                    ip.* = .{};
                    ip.base.pageId = newRootPageId;
                    ip.base.size = 2;
                    ip.keys[1] = key;
                    ip.vals[0] = leaf.base.pageId;
                    ip.vals[1] = newLeaf.base.pageId;
                    self.rootPageId = newRootPageId;
                    leaf.base.parentPageId = newRootPageId;
                    newLeaf.base.parentPageId = newRootPageId;
                }
                return;
            }
            // Else, get the parent.
            if (try self.bpm.getWritePage(leaf.base.parentPageId.?)) |wp| {
                var p = wp;
                defer p.drop() catch {};
                var pp: *InternalPage = @ptrCast(@alignCast(p.getDataMut().ptr));
                if (!pp.base.isFull()) {
                    pp.insertAt(pp.valueAt(leaf.base.pageId) + 1, key, newLeaf.base.pageId);
                }
                newLeaf.base.parentPageId = leaf.base.parentPageId;
            }
        }
    };
}
