const std = @import("std");

const PageId = @import("page.zig").PageId;
const WritePage = @import("buffer_pool_manager.zig").WritePage;
const BasePage = @import("btree_page.zig").BasePage;
const InternalPage = @import("btree_page.zig").InternalPage;
const LeafPage = @import("btree_page.zig").LeafPage;
const BufferPoolManager = @import("buffer_pool_manager.zig").BufferPoolManager;
const Rid = @import("rid.zig").Rid;

pub fn Btree(
    comptime Key: type,
    comptime cmp: fn (lsh: Key, rhs: Key) i32,
    comptime maxLeafSize: ?usize,
    comptime maxInternalSize: ?usize,
    comptime tombCount: ?usize,
) type {
    const Base = BasePage(Key, cmp);
    const Internal = InternalPage(Key, cmp, maxInternalSize);
    const Leaf = LeafPage(Key, cmp, maxLeafSize, tombCount);

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

        pub fn find(self: *const Self, key: Key) !?Rid {
            if (self.rootPageId == null) return null;

            var leaf: *const Leaf = undefined;
            var searchPageId = self.rootPageId.?;
            while (true) {
                var p = (try self.bpm.getReadPage(searchPageId)).?;
                const base: *const Base = @ptrCast(@alignCast(p.getData().ptr));

                switch (base.pageType) {
                    .leaf => {
                        leaf = @ptrCast(@alignCast(p.getData().ptr));
                        p.drop();
                        break;
                    },
                    .internal => {
                        const ip: *const Internal = @ptrCast(@alignCast(p.getData().ptr));
                        searchPageId = ip.pageIdOf(key);
                        p.drop();
                    },
                }
            }
            return leaf.find(key);
        }

        pub fn insert(self: *Self, key: Key, rid: Rid) !void {
            var leaf: *Leaf = undefined;
            var page: WritePage = undefined;
            defer page.drop();

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
                    const p: *const Base = @ptrCast(@alignCast(wp.getData().ptr));

                    switch (p.pageType) {
                        .leaf => {
                            page = wp;
                            leaf = @ptrCast(@alignCast(page.getDataMut().ptr));
                            break;
                        },
                        .internal => {
                            const ip: *const Internal = @ptrCast(@alignCast(wp.getData().ptr));
                            searchPageId = ip.pageIdOf(key);
                            wp.drop();
                        },
                    }
                }
            }

            if (!leaf.base.isFull()) {
                leaf.insert(key, rid);
            } else {
                // Split the leaf.
                const newPageId = self.bpm.newPage();
                var p = (try self.bpm.getWritePage(newPageId)).?;
                defer p.drop();

                var newLeaf: *Leaf = @ptrCast(@alignCast(p.getDataMut().ptr));
                newLeaf.* = .init(newPageId);
                var tmpLeaf: Leaf = leaf.clone();
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

        fn insertInParent(self: *Self, base1: *Base, key: Key, base2: *Base) !void {
            // Root page.
            if (base1.pageId == self.rootPageId) {
                const newRootPageId = self.bpm.newPage();
                var p = (try self.bpm.getWritePage(newRootPageId)).?;
                defer p.drop();
                const ip: *Internal = @ptrCast(@alignCast(p.getDataMut().ptr));
                ip.* = .init(newRootPageId, base1.pageId, key, base2.pageId);
                self.rootPageId = newRootPageId;
                return;
            }
            // Else, get the parent.
            var p = (try self.bpm.getWritePage(try self.parentPageIdOf(base1, key))).?;
            defer p.drop();
            var parent: *Internal = @ptrCast(@alignCast(p.getDataMut().ptr));
            if (!parent.base.isFull()) {
                parent.insertAt(
                    parent.findVal(base1.pageId).? + 1,
                    key,
                    base2.pageId,
                );
                return;
            }
            // Split the parent.
            const newPageId = self.bpm.newPage();
            var p2 = (try self.bpm.getWritePage(newPageId)).?;
            defer p2.drop();
            var newParent: *Internal = @ptrCast(@alignCast(p2.getDataMut().ptr));
            newParent.* = .init(newPageId, undefined, undefined, undefined);
            var tmpParent: Internal = parent.clone();
            tmpParent.insertAt(tmpParent.findVal(base1.pageId).? + 1, key, base2.pageId);
            const splitAt = tmpParent.base.size / 2;
            parent.fillFrom(tmpParent, 0, splitAt);
            newParent.fillFrom(tmpParent, splitAt, tmpParent.base.size);
            try self.insertInParent(&parent.base, tmpParent.keys[splitAt], &newParent.base);
        }

        fn parentPageIdOf(self: *const Self, base: *const Base, key: Key) !PageId {
            // Searching from the root should not run into lock contention at this point.
            var result = self.rootPageId.?;
            while (true) {
                var rp = (try self.bpm.getReadPage(result)).?;
                defer rp.drop();
                const p: *const Internal = @ptrCast(@alignCast(rp.getData().ptr));
                if (p.findVal(base.pageId) != null) return result;
                result = p.pageIdOf(key);
            }
        }
    };
}
