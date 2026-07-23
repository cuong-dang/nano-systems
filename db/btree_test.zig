const std = @import("std");
const testing = std.testing;
const expectEqual = std.testing.expectEqual;
const gpa = std.testing.allocator;

const PageId = @import("page.zig").PageId;
const Btree = @import("btree.zig").Btree;
const BasePage = @import("btree_page.zig").BasePage;
const LeafPage = @import("btree_page.zig").LeafPage;
const InternalPage = @import("btree_page.zig").InternalPage;
const BufferPoolManager = @import("buffer_pool_manager.zig").BufferPoolManager;
const DiskManager = @import("disk_manager.zig").DiskManager;
const Rid = @import("rid.zig").Rid;
const PageType = @import("btree_page.zig").PageType;

fn intCmp(lhs: i64, rhs: i64) i32 {
    if (lhs < rhs) return -1;
    if (lhs > rhs) return 1;
    return 0;
}
const Tree = Btree(
    i64,
    intCmp,
    2, // leaf max size
    3, // internal max size
    0, // tombstones
);
const Base = BasePage(i64, intCmp);
const Leaf = LeafPage(i64, intCmp, 2, 0);
const Internal = InternalPage(i64, intCmp, 3);

test "bustub::BasicInsertTest" {
    const cwd = try std.process.currentPathAlloc(std.Options.debug_io, gpa);
    defer gpa.free(cwd);
    const dbPath = try std.fs.path.resolve(gpa, &.{ cwd, "./test.db" });
    defer gpa.free(dbPath);
    var dm = try DiskManager.init(gpa, std.Options.debug_io, dbPath);
    defer dm.deinit();
    const bpm = try BufferPoolManager.init(gpa, std.Options.debug_io, 50, &dm);
    defer bpm.deinit();
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.Options.debug_io, dbPath) catch {};

    // Allocate header page
    const headerPageId = bpm.newPage();
    var tree = Tree.init(gpa, "foo_pk", headerPageId, bpm);

    try tree.insert(0, rid(0));
    try expectEqual(rid(0), try tree.find(0));
    try expectEqual(null, try tree.find(1));

    // Verify root exists
    try testing.expect(tree.rootPageId != null);
    const rootPageId = tree.rootPageId.?;
    var rootGuard = (try bpm.getReadPage(rootPageId)).?;

    const base: *const Base = @ptrCast(@alignCast(rootGuard.getData().ptr));
    try expectEqual(PageType.leaf, base.pageType);

    const leaf: *const Leaf = @ptrCast(@alignCast(rootGuard.getData().ptr));

    try expectEqual(1, leaf.base.size);
    try expectEqual(0, leaf.keys[0]);
    try expectEqual(rid(0), leaf.vals[0]);

    rootGuard.drop();
}

test "split leaf" {
    const cwd = try std.process.currentPathAlloc(std.Options.debug_io, gpa);
    defer gpa.free(cwd);
    const dbPath = try std.fs.path.resolve(gpa, &.{ cwd, "./test.db" });
    defer gpa.free(dbPath);
    var dm = try DiskManager.init(gpa, std.Options.debug_io, dbPath);
    defer dm.deinit();
    const bpm = try BufferPoolManager.init(gpa, std.Options.debug_io, 50, &dm);
    defer bpm.deinit();
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.Options.debug_io, dbPath) catch {};

    const headerPageId = bpm.newPage();
    var tree = Tree.init(gpa, "foo_pk", headerPageId, bpm);
    // Ops.
    try tree.insert(0, rid(0));
    try tree.insert(1, rid(1));
    try tree.insert(2, rid(2));
    try expectEqual(rid(0), try tree.find(0));
    try expectEqual(rid(1), try tree.find(1));
    try expectEqual(rid(2), try tree.find(2));

    // Expects.
    // Assuming 3 pages.
    // root
    try expectEqual(3, tree.rootPageId);
    try expectInternal(bpm, 3, .{
        .base = .{
            .pageType = .internal,
            .maxSize = 3,
            .size = 2,
            .pageId = 3,
        },
        .keys = .{ undefined, 1, undefined, undefined },
        .vals = .{ 1, 2, undefined, undefined },
    });

    // leaf 1
    try expectLeaf(bpm, 1, .{
        .base = .{
            .pageType = .leaf,
            .maxSize = 2,
            .size = 1,
            .pageId = 1,
        },
        .keys = .{ 0, undefined, undefined },
        .vals = .{ rid(0), undefined, undefined },
        .nextPageId = 2,
    });
    // leaf 2
    try expectLeaf(bpm, 2, .{
        .base = .{
            .pageType = .leaf,
            .maxSize = 2,
            .size = 2,
            .pageId = 2,
        },
        .keys = .{ 1, 2, undefined },
        .vals = .{ rid(1), rid(2), undefined },
        .nextPageId = null,
    });
}

test "split parent" {
    const cwd = try std.process.currentPathAlloc(std.Options.debug_io, gpa);
    defer gpa.free(cwd);
    const dbPath = try std.fs.path.resolve(gpa, &.{ cwd, "./test.db" });
    defer gpa.free(dbPath);
    var dm = try DiskManager.init(gpa, std.Options.debug_io, dbPath);
    defer dm.deinit();
    const bpm = try BufferPoolManager.init(gpa, std.Options.debug_io, 50, &dm);
    defer bpm.deinit();
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.Options.debug_io, dbPath) catch {};

    const headerPageId = bpm.newPage();
    var tree = Tree.init(gpa, "foo_pk", headerPageId, bpm);

    try tree.insert(0, rid(0));
    try tree.insert(1, rid(1));
    try tree.insert(2, rid(2));
    try tree.insert(3, rid(3));
    try expectEqual(rid(0), try tree.find(0));
    try expectEqual(rid(1), try tree.find(1));
    try expectEqual(rid(2), try tree.find(2));
    try expectEqual(rid(3), try tree.find(3));

    // Root should still be page 3.
    try expectEqual(@as(?PageId, 3), tree.rootPageId);
    // root 3
    try expectInternal(bpm, 3, .{
        .base = .{
            .pageType = .internal,
            .maxSize = 3,
            .size = 3,
            .pageId = 3,
        },
        .keys = .{ undefined, 1, 2, undefined },
        .vals = .{ 1, 2, 4, undefined },
    });
    // leaf 1
    try expectLeaf(bpm, 1, .{
        .base = .{
            .pageType = .leaf,
            .maxSize = 2,
            .size = 1,
            .pageId = 1,
        },
        .keys = .{ 0, undefined, undefined },
        .vals = .{ rid(0), undefined, undefined },
        .nextPageId = 2,
    });
    // leaf 2
    try expectLeaf(bpm, 2, .{
        .base = .{
            .pageType = .leaf,
            .maxSize = 2,
            .size = 1,
            .pageId = 2,
        },
        .keys = .{ 1, undefined, undefined },
        .vals = .{ rid(1), undefined, undefined },
        .nextPageId = 4,
    });
    // leaf 4
    try expectLeaf(bpm, 4, .{
        .base = .{
            .pageType = .leaf,
            .maxSize = 2,
            .size = 2,
            .pageId = 4,
        },
        .keys = .{ 2, 3, undefined },
        .vals = .{ rid(2), rid(3), undefined },
        .nextPageId = null,
    });

    // recursively splitting parents
    try tree.insert(4, rid(4));
    try expectEqual(rid(4), try tree.find(4));
    try expectEqual(@as(?PageId, 7), tree.rootPageId);
    // expect from bottom
    // leaf page 1
    try expectLeaf(bpm, 1, .{
        .base = .{
            .pageType = .leaf,
            .maxSize = 2,
            .size = 1,
            .pageId = 1,
        },
        .keys = .{ 0, undefined, undefined },
        .vals = .{ rid(0), undefined, undefined },
        .nextPageId = 2,
    });
    // leaf page 2
    try expectLeaf(bpm, 2, .{
        .base = .{
            .pageType = .leaf,
            .maxSize = 2,
            .size = 1,
            .pageId = 2,
        },
        .keys = .{ 1, undefined, undefined },
        .vals = .{ rid(1), undefined, undefined },
        .nextPageId = 4,
    });
    // leaf page 4
    try expectLeaf(bpm, 4, .{
        .base = .{
            .pageType = .leaf,
            .maxSize = 2,
            .size = 1,
            .pageId = 4,
        },
        .keys = .{ 2, undefined, undefined },
        .vals = .{ rid(2), undefined, undefined },
        .nextPageId = 5,
    });
    // leaf page 5
    try expectLeaf(bpm, 5, .{
        .base = .{
            .pageType = .leaf,
            .maxSize = 2,
            .size = 2,
            .pageId = 5,
        },
        .keys = .{ 3, 4, undefined },
        .vals = .{ rid(3), rid(4), undefined },
        .nextPageId = null,
    });

    // internal page 3
    try expectInternal(bpm, 3, .{
        .base = .{
            .pageType = .internal,
            .maxSize = 3,
            .size = 2,
            .pageId = 3,
        },
        .keys = .{ undefined, 1, undefined, undefined },
        .vals = .{ 1, 2, undefined, undefined },
    });
    // internal page 6
    try expectInternal(bpm, 6, .{
        .base = .{
            .pageType = .internal,
            .maxSize = 3,
            .size = 2,
            .pageId = 6,
        },
        .keys = .{ undefined, 3, undefined, undefined },
        .vals = .{ 4, 5, undefined, undefined },
    });
    // root
    try expectInternal(bpm, 7, .{
        .base = .{
            .pageType = .internal,
            .maxSize = 3,
            .size = 2,
            .pageId = 7,
        },
        .keys = .{ undefined, 2, undefined, undefined },
        .vals = .{ 3, 6, undefined, undefined },
    });
}

test "insert descending order" {
    const cwd = try std.process.currentPathAlloc(std.Options.debug_io, gpa);
    defer gpa.free(cwd);
    const dbPath = try std.fs.path.resolve(gpa, &.{ cwd, "./test.db" });
    defer gpa.free(dbPath);
    var dm = try DiskManager.init(gpa, std.Options.debug_io, dbPath);
    defer dm.deinit();
    const bpm = try BufferPoolManager.init(gpa, std.Options.debug_io, 50, &dm);
    defer bpm.deinit();
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.Options.debug_io, dbPath) catch {};

    const headerPageId = bpm.newPage();
    var tree = Tree.init(gpa, "foo_pk", headerPageId, bpm);

    try tree.insert(7, rid(7));
    try tree.insert(6, rid(6));
    try tree.insert(5, rid(5));
    try tree.insert(4, rid(4));
    try tree.insert(3, rid(3));
    try tree.insert(2, rid(2));
    try tree.insert(1, rid(1));
    try tree.insert(0, rid(0));
    try expectEqual(rid(0), try tree.find(0));
    try expectEqual(rid(1), try tree.find(1));
    try expectEqual(rid(2), try tree.find(2));
    try expectEqual(rid(3), try tree.find(3));
    try expectEqual(rid(4), try tree.find(4));
    try expectEqual(rid(5), try tree.find(5));
    try expectEqual(rid(6), try tree.find(6));
    try expectEqual(rid(7), try tree.find(7));

    try expectEqual(@as(?PageId, 7), tree.rootPageId);
    // expect from bottom
    // leaf 1
    try expectLeaf(bpm, 1, .{
        .base = .{
            .pageType = .leaf,
            .maxSize = 2,
            .size = 2,
            .pageId = 1,
        },
        .keys = .{ 0, 1, undefined },
        .vals = .{ rid(0), rid(1), undefined },
        .nextPageId = 5,
    });
    // leaf 5
    try expectLeaf(bpm, 5, .{
        .base = .{
            .pageType = .leaf,
            .maxSize = 2,
            .size = 2,
            .pageId = 5,
        },
        .keys = .{ 2, 3, undefined },
        .vals = .{ rid(2), rid(3), undefined },
        .nextPageId = 4,
    });
    // leaf 4
    try expectLeaf(bpm, 4, .{
        .base = .{
            .pageType = .leaf,
            .maxSize = 2,
            .size = 2,
            .pageId = 4,
        },
        .keys = .{ 4, 5, undefined },
        .vals = .{ rid(4), rid(5), undefined },
        .nextPageId = 2,
    });
    // leaf 2
    try expectLeaf(bpm, 2, .{
        .base = .{
            .pageType = .leaf,
            .maxSize = 2,
            .size = 2,
            .pageId = 2,
        },
        .keys = .{ 6, 7, undefined },
        .vals = .{ rid(6), rid(7), undefined },
        .nextPageId = null,
    });
    // internal 3
    try expectInternal(bpm, 3, .{
        .base = .{
            .pageType = .internal,
            .maxSize = 3,
            .size = 2,
            .pageId = 3,
        },
        .keys = .{ undefined, 2, undefined, undefined },
        .vals = .{ 1, 5, undefined, undefined },
    });
    // internal 6
    try expectInternal(bpm, 6, .{
        .base = .{
            .pageType = .internal,
            .maxSize = 3,
            .size = 2,
            .pageId = 6,
        },
        .keys = .{ undefined, 6, undefined, undefined },
        .vals = .{ 4, 2, undefined, undefined },
    });
    // root 7
    try expectInternal(bpm, 7, .{
        .base = .{
            .pageType = .internal,
            .maxSize = 3,
            .size = 2,
            .pageId = 7,
        },
        .keys = .{ undefined, 4, undefined, undefined },
        .vals = .{ 3, 6, undefined, undefined },
    });
}

fn rid(i: u32) Rid {
    return .{ .pageId = i, .slotNum = i };
}

fn expectLeaf(
    bpm: *BufferPoolManager,
    pageId: PageId,
    expected: Leaf,
) !void {
    var leafPage = (try bpm.getReadPage(pageId)).?;
    defer leafPage.drop();
    const base: *const Base = @ptrCast(@alignCast(leafPage.getData().ptr));
    try expectEqual(PageType.leaf, base.pageType);

    const leaf: *const Leaf = @ptrCast(@alignCast(leafPage.getData().ptr));
    try expectEqual(expected.base, leaf.base);
    for (0..leaf.base.size) |i| {
        try expectEqual(expected.keys[i], leaf.keys[i]);
        try expectEqual(expected.vals[i], leaf.vals[i]);
    }
    try expectEqual(expected.nextPageId, leaf.nextPageId);
}

fn expectInternal(
    bpm: *BufferPoolManager,
    pageId: PageId,
    expected: Internal,
) !void {
    var ip = (try bpm.getReadPage(pageId)).?;
    defer ip.drop();
    const base: *const Base = @ptrCast(@alignCast(ip.getData().ptr));
    try expectEqual(PageType.internal, base.pageType);

    const internal: *const Internal = @ptrCast(@alignCast(ip.getData().ptr));
    try expectEqual(expected.base, internal.base);
    try expectEqual(expected.vals[0], internal.vals[0]);
    for (1..internal.base.size) |i| {
        try expectEqual(expected.keys[i], internal.keys[i]);
        try expectEqual(expected.vals[i], internal.vals[i]);
    }
}
