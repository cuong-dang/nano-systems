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
                    leaf.* = .init(self.rootPageId.?);
                } else {
                    return;
                }
            } else {
                // Find the leaf node that should contain key K.
                var searchPageId = self.rootPageId.?;
                while (true) {
                    var wp = (try self.bpm.getWritePage(searchPageId)).?;
                    const p: *const BasePage = @ptrCast(@alignCast(wp.getData().ptr));

                    switch (p.pageType) {
                        .leaf => {
                            page = wp;
                            leaf = @ptrCast(@alignCast(page.getDataMut().ptr));
                            break;
                        },
                        .internal => {
                            const ip: *const InternalPage = @ptrCast(@alignCast(wp.getData().ptr));
                            searchPageId = ip.vals[p.findLastLe(&ip.keys, key, 1)];
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
                    var p = wp;
                    defer p.drop() catch {};
                    var newLeaf: *LeafPage = @ptrCast(@alignCast(p.getDataMut().ptr));
                    newLeaf.* = .init(newPageId);
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
                    try self.insertInParent(&leaf.base, newLeaf.keys[0], &newLeaf.base);
                }
            }
        }

        fn insertInParent(self: *Self, base1: *BasePage, key: Key, base2: *BasePage) !void {
            // Root page.
            if (base1.pageId == self.rootPageId) {
                const newRootPageId = self.bpm.newPage();
                if (try self.bpm.getWritePage(newRootPageId)) |wp| {
                    var p = wp;
                    defer p.drop() catch {};
                    var ip: *InternalPage = @ptrCast(@alignCast(p.getDataMut().ptr));
                    ip.* = .init(newRootPageId);
                    ip.base.size = 2;
                    ip.keys[1] = key;
                    ip.vals[0] = base1.pageId;
                    ip.vals[1] = base2.pageId;
                    self.rootPageId = newRootPageId;
                    base1.parentPageId = newRootPageId;
                    base2.parentPageId = newRootPageId;
                }
                return;
            }
            // Else, get the parent.
            if (try self.bpm.getWritePage(base1.parentPageId.?)) |wp| {
                var p = wp;
                defer p.drop() catch {};
                var parent: *InternalPage = @ptrCast(@alignCast(p.getDataMut().ptr));
                if (!parent.base.isFull()) {
                    parent.insertAt(
                        parent.valueAt(base1.pageId) + 1,
                        key,
                        base2.pageId,
                    );
                    base2.parentPageId = base1.parentPageId;
                    return;
                }
                // Split the parent.
                const newPageId = self.bpm.newPage();
                if (try self.bpm.getWritePage(newPageId)) |wp2| {
                    var p2 = wp2;
                    defer p2.drop() catch {};
                    var newParent: *InternalPage = @ptrCast(@alignCast(p2.getDataMut().ptr));
                    newParent.* = .init(newPageId);
                    var tmpParent: InternalPage = parent.clone();
                    tmpParent.insertAt(tmpParent.valueAt(base1.pageId) + 1, key, base2.pageId);
                    parent.fillFrom(tmpParent, 0, tmpParent.base.size / 2);
                    newParent.fillFrom(tmpParent, tmpParent.base.size / 2, tmpParent.base.size);
                    try self.insertInParent(&parent.base, newParent.keys[1], &newParent.base);
                }
            }
        }
    };
}
