const std = @import("std");
const testing = std.testing;
const expectEqual = std.testing.expectEqual;

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
    const gpa = testing.allocator;

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

    try rootGuard.drop();
}

test "first split" {
    const gpa = testing.allocator;

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

    // Expects.
    // Assuming 3 pages.
    // root
    try expectInternal(bpm, 3, .{
        .base = .{ .pageType = .internal, .maxSize = 3, .size = 2 },
        .keys = .{ undefined, 1, undefined },
        .vals = .{ 1, 2, undefined },
    });

    // leaf 1
    try expectLeaf(bpm, 1, .{
        .base = .{ .pageType = .leaf, .maxSize = 2, .size = 1 },
        .keys = .{ 0, undefined, undefined },
        .vals = .{ rid(0), undefined, undefined },
        .nextPageId = 2,
    });
    // leaf 2
    try expectLeaf(bpm, 2, .{
        .base = .{ .pageType = .leaf, .maxSize = 2, .size = 2 },
        .keys = .{ 1, 2, undefined },
        .vals = .{ rid(1), rid(2), undefined },
        .nextPageId = null,
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
    defer leafPage.drop() catch {};
    const base: *const Base = @ptrCast(@alignCast(leafPage.getData().ptr));
    try expectEqual(PageType.leaf, base.pageType);

    const leaf: *const Leaf = @ptrCast(@alignCast(leafPage.getData().ptr));
    try expectEqual(expected.base, leaf.base);
    for (0..leaf.base.size) |i| {
        try expectEqual(expected.keys[i], leaf.keys[i]);
        try expectEqual(expected.vals[i], leaf.vals[i]);
    }
    try expectEqual(expected.nextPageId, leaf.nextPageId);
    try expectEqual(expected.parentPageId, leaf.parentPageId);
}

fn expectInternal(
    bpm: *BufferPoolManager,
    pageId: PageId,
    expected: Internal,
) !void {
    var ip = (try bpm.getReadPage(pageId)).?;
    defer ip.drop() catch {};
    const base: *const Base = @ptrCast(@alignCast(ip.getData().ptr));
    try expectEqual(PageType.internal, base.pageType);

    const internal: *const Internal = @ptrCast(@alignCast(ip.getData().ptr));
    try expectEqual(expected.base, internal.base);
    try expectEqual(expected.vals[0], internal.vals[0]);
    for (1..internal.base.size) |i| {
        try expectEqual(expected.keys[i], internal.keys[i]);
        try expectEqual(expected.vals[i], internal.vals[i]);
    }
    try expectEqual(expected.parentPageId, internal.parentPageId);
}
