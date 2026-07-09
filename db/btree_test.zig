const std = @import("std");
const testing = std.testing;

const Btree = @import("btree.zig").Btree;
const BasePage = @import("btree_page.zig").BasePage;
const LeafPage = @import("btree_page.zig").LeafPage;
const BufferPoolManager = @import("buffer_pool_manager.zig").BufferPoolManager;
const DiskManager = @import("disk_manager.zig").DiskManager;
const Rid = @import("rid.zig").Rid;
const PageType = @import("btree_page.zig").PageType;

fn intCmp(lhs: i64, rhs: i64) i32 {
    if (lhs < rhs) return -1;
    if (lhs > rhs) return 1;
    return 0;
}

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
    const Tree = Btree(
        i64,
        intCmp,
        2, // leaf max size
        3, // internal max size
        0, // tombstones
    );
    var tree = Tree.init(gpa, "foo_pk", headerPageId, bpm);

    const rid: Rid = .{ .pageId = 42, .slotNum = 43 };

    try tree.insert(0, rid);

    // Verify root exists
    try testing.expect(tree.rootPageId != null);
    const rootPageId = tree.rootPageId.?;
    var rootGuard = (try bpm.getReadPage(rootPageId)).?;

    const base: *const BasePage = @ptrCast(@alignCast(rootGuard.getData().ptr));
    try testing.expectEqual(PageType.leaf, base.pageType);

    const Leaf = LeafPage(i64, 2, 0);
    const leaf: *const Leaf = @ptrCast(@alignCast(rootGuard.getData().ptr));

    try testing.expectEqual(1, leaf.base.size);
    try testing.expectEqual(0, leaf.keys[0].?);
    try testing.expectEqual(rid, leaf.vals[0]);

    try rootGuard.drop();
}
