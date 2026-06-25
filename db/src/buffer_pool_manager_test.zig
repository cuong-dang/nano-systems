const std = @import("std");
const testing = std.testing;
const gpa = testing.allocator;
const io = testing.io;

const page = @import("./page.zig");
const DiskManager = @import("./disk_manager.zig").DiskManager;
const BufferPoolManager = @import("buffer_pool_manager.zig").BufferPoolManager;

test "write and read a page" {
    const cwd = try std.process.currentPathAlloc(io, gpa);
    const testDbPath = try std.fs.path.resolve(gpa, &.{ cwd, "./test.db" });
    var dm: DiskManager = try .init(gpa, io, testDbPath);
    const bpm = try BufferPoolManager.init(gpa, io, 8, &dm);
    defer gpa.free(cwd);
    defer gpa.free(testDbPath);
    defer dm.deinit();
    defer bpm.deinit();
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), io, testDbPath) catch unreachable;

    const page0 = bpm.newPage();
    var writePage = (try bpm.getWritePage(page0)).?;
    try testing.expectEqual(page0, writePage.getPageId());
    try testing.expect(!writePage.isDirty());

    const data = "hello, db";
    @memcpy(writePage.getDataMut()[0..data.len], data);
    try testing.expect(writePage.isDirty());
    try writePage.flush();
    try writePage.release();

    var readPage = (try bpm.getReadPage(page0)).?;
    try testing.expectEqualSlices(u8, data, readPage.getData()[0..data.len]);
    try readPage.release();
}
