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

test "bustub::PagePinEasyTest" {
    const cwd = try std.process.currentPathAlloc(io, gpa);
    const testDbPath = try std.fs.path.resolve(gpa, &.{ cwd, "./test.db" });
    var dm: DiskManager = try .init(gpa, io, testDbPath);
    const bpm = try BufferPoolManager.init(gpa, io, 2, &dm);
    defer gpa.free(cwd);
    defer gpa.free(testDbPath);
    defer dm.deinit();
    defer bpm.deinit();
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), io, testDbPath) catch unreachable;

    const pid0 = bpm.newPage();
    const pid1 = bpm.newPage();
    const s0 = "page0";
    const s1 = "page1";
    const s0u = "page0updated";
    const s1u = "page1updated";

    // The following was ported over by ChatGPT.
    {
        var page0_write = (try bpm.getWritePage(pid0)).?;
        defer page0_write.release() catch unreachable;
        @memcpy(page0_write.getDataMut()[0..s0.len], s0);

        var page1_write = (try bpm.getWritePage(pid1)).?;
        defer page1_write.release() catch unreachable;
        @memcpy(page1_write.getDataMut()[0..s1.len], s1);

        try std.testing.expectEqual(@as(?usize, 1), bpm.getPinCount(pid0));
        try std.testing.expectEqual(@as(?usize, 1), bpm.getPinCount(pid1));

        const temp_pid1 = bpm.newPage();
        try std.testing.expect((try bpm.getReadPage(temp_pid1)) == null);
        const temp_pid2 = bpm.newPage();
        try std.testing.expect((try bpm.getWritePage(temp_pid2)) == null);

        try std.testing.expectEqual(@as(?usize, 1), bpm.getPinCount(pid0));
        page0_write.release() catch unreachable;
        try std.testing.expectEqual(@as(?usize, 0), bpm.getPinCount(pid0));
        try std.testing.expectEqual(@as(?usize, 1), bpm.getPinCount(pid1));
        page1_write.release() catch unreachable;
        try std.testing.expectEqual(@as(?usize, 0), bpm.getPinCount(pid1));
    }

    {
        const temp_pid1 = bpm.newPage();
        var temp_page1 = (try bpm.getReadPage(temp_pid1)).?;
        defer temp_page1.release() catch unreachable;
        const temp_pid2 = bpm.newPage();
        var temp_page2 = (try bpm.getWritePage(temp_pid2)).?;
        defer temp_page2.release() catch unreachable;

        try std.testing.expectEqual(@as(?usize, null), bpm.getPinCount(pid0));
        try std.testing.expectEqual(@as(?usize, null), bpm.getPinCount(pid1));
    }

    {
        var page0_write = (try bpm.getWritePage(pid0)).?;
        defer page0_write.release() catch unreachable;

        try std.testing.expectEqualStrings(s0, std.mem.sliceTo(
            page0_write.getData(),
            0,
        ));
        @memcpy(page0_write.getDataMut()[0..s0u.len], s0u);

        var page1_write = (try bpm.getWritePage(pid1)).?;
        defer page1_write.release() catch unreachable;
        try std.testing.expectEqualStrings(
            s1,
            std.mem.sliceTo(page1_write.getData(), 0),
        );

        @memcpy(page1_write.getDataMut()[0..s1u.len], s1u);

        try std.testing.expectEqual(@as(?usize, 1), bpm.getPinCount(pid0));
        try std.testing.expectEqual(@as(?usize, 1), bpm.getPinCount(pid1));
    }

    try std.testing.expectEqual(@as(?usize, 0), bpm.getPinCount(pid0));
    try std.testing.expectEqual(@as(?usize, 0), bpm.getPinCount(pid1));

    {
        var page0_read = (try bpm.getReadPage(pid0)).?;
        defer page0_read.release() catch unreachable;
        try std.testing.expectEqualStrings(
            s0u,
            std.mem.sliceTo(page0_read.getData(), 0),
        );

        var page1_read = (try bpm.getReadPage(pid1)).?;
        defer page1_read.release() catch unreachable;
        try std.testing.expectEqualStrings(
            s1u,
            std.mem.sliceTo(page1_read.getData(), 0),
        );

        try std.testing.expectEqual(@as(?usize, 1), bpm.getPinCount(pid0));
        try std.testing.expectEqual(@as(?usize, 1), bpm.getPinCount(pid1));
    }

    try std.testing.expectEqual(@as(?usize, 0), bpm.getPinCount(pid0));
    try std.testing.expectEqual(@as(?usize, 0), bpm.getPinCount(pid1));
}
