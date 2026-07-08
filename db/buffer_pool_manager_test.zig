const std = @import("std");
const testing = std.testing;
const gpa = testing.allocator;
const io = testing.io;

const pageSize = @import("page.zig").size;
const PageId = @import("page.zig").PageId;
const DiskManager = @import("./disk_manager.zig").DiskManager;
const BufferPoolManager = @import("buffer_pool_manager.zig").BufferPoolManager;
const WritePage = @import("buffer_pool_manager.zig").WritePage;

const FRAMES = 10;

// Most BusTub tests are ported over by ChatGPT.

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
    try writePage.drop();

    var readPage = (try bpm.getReadPage(page0)).?;
    try testing.expectEqualSlices(u8, data, readPage.getData()[0..data.len]);
    try readPage.drop();
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

    {
        var page0_write = (try bpm.getWritePage(pid0)).?;
        defer page0_write.drop() catch unreachable;
        @memcpy(page0_write.getDataMut()[0..s0.len], s0);

        var page1_write = (try bpm.getWritePage(pid1)).?;
        defer page1_write.drop() catch unreachable;
        @memcpy(page1_write.getDataMut()[0..s1.len], s1);

        try std.testing.expectEqual(@as(?usize, 1), bpm.getPinCount(pid0));
        try std.testing.expectEqual(@as(?usize, 1), bpm.getPinCount(pid1));

        const temp_pid1 = bpm.newPage();
        try std.testing.expect((try bpm.getReadPage(temp_pid1)) == null);
        const temp_pid2 = bpm.newPage();
        try std.testing.expect((try bpm.getWritePage(temp_pid2)) == null);

        try std.testing.expectEqual(@as(?usize, 1), bpm.getPinCount(pid0));
        page0_write.drop() catch unreachable;
        try std.testing.expectEqual(@as(?usize, 0), bpm.getPinCount(pid0));
        try std.testing.expectEqual(@as(?usize, 1), bpm.getPinCount(pid1));
        page1_write.drop() catch unreachable;
        try std.testing.expectEqual(@as(?usize, 0), bpm.getPinCount(pid1));
    }

    {
        const temp_pid1 = bpm.newPage();
        var temp_page1 = (try bpm.getReadPage(temp_pid1)).?;
        defer temp_page1.drop() catch unreachable;
        const temp_pid2 = bpm.newPage();
        var temp_page2 = (try bpm.getWritePage(temp_pid2)).?;
        defer temp_page2.drop() catch unreachable;

        try std.testing.expectEqual(@as(?usize, null), bpm.getPinCount(pid0));
        try std.testing.expectEqual(@as(?usize, null), bpm.getPinCount(pid1));
    }

    {
        var page0_write = (try bpm.getWritePage(pid0)).?;
        defer page0_write.drop() catch unreachable;

        try std.testing.expectEqualStrings(s0, std.mem.sliceTo(
            page0_write.getData(),
            0,
        ));
        @memcpy(page0_write.getDataMut()[0..s0u.len], s0u);

        var page1_write = (try bpm.getWritePage(pid1)).?;
        defer page1_write.drop() catch unreachable;
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
        defer page0_read.drop() catch unreachable;
        try std.testing.expectEqualStrings(
            s0u,
            std.mem.sliceTo(page0_read.getData(), 0),
        );

        var page1_read = (try bpm.getReadPage(pid1)).?;
        defer page1_read.drop() catch unreachable;
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

test "bustub::PagePinMediumTest" {
    const cwd = try std.process.currentPathAlloc(io, gpa);
    const testDbPath = try std.fs.path.resolve(gpa, &.{ cwd, "./test.db" });
    var dm: DiskManager = try .init(gpa, io, testDbPath);
    const bpm = try BufferPoolManager.init(gpa, io, FRAMES, &dm);

    defer gpa.free(cwd);
    defer gpa.free(testDbPath);
    defer dm.deinit();
    defer bpm.deinit();
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), io, testDbPath) catch unreachable;

    const pid0 = bpm.newPage();
    {
        var page0 = (try bpm.getWritePage(pid0)).?;
        defer page0.drop() catch unreachable;

        const hello = "Hello";
        @memcpy(page0.getDataMut()[0..hello.len], hello);

        try std.testing.expectEqualStrings(
            hello,
            std.mem.sliceTo(page0.getData(), 0),
        );
    }

    var pages: std.ArrayList(WritePage) = .empty;
    defer {
        for (pages.items) |*page| {
            page.drop() catch unreachable;
        }
        pages.deinit(gpa);
    }

    // Fill the buffer pool.
    for (0..FRAMES) |_| {
        const pid = bpm.newPage();
        const page = (try bpm.getWritePage(pid)).?;
        try pages.append(gpa, page);
    }

    // All pin counts should be 1.
    for (pages.items) |*page| {
        try std.testing.expectEqual(
            @as(?usize, 1),
            bpm.getPinCount(page.getPageId()),
        );
    }

    // No more pages can be fetched.
    for (0..FRAMES) |_| {
        const pid = bpm.newPage();
        try std.testing.expect((try bpm.getWritePage(pid)) == null);
    }

    // Drop half of them.
    for (0..FRAMES / 2) |_| {
        var page = pages.orderedRemove(0);
        const pid = page.getPageId();

        try std.testing.expectEqual(
            @as(?usize, 1),
            bpm.getPinCount(pid),
        );

        try page.drop();

        try std.testing.expectEqual(
            @as(?usize, 0),
            bpm.getPinCount(pid),
        );
    }

    // Remaining pages are still pinned.
    for (pages.items) |*page| {
        try std.testing.expectEqual(
            @as(?usize, 1),
            bpm.getPinCount(page.getPageId()),
        );
    }

    // Allocate replacement pages.
    for (0..((FRAMES / 2) - 1)) |_| {
        const pid = bpm.newPage();
        const page = (try bpm.getWritePage(pid)).?;
        try pages.append(gpa, page);
    }

    // Original page should still be readable.
    {
        var original = (try bpm.getReadPage(pid0)).?;
        defer original.drop() catch unreachable;

        try std.testing.expectEqualStrings(
            "Hello",
            std.mem.sliceTo(original.getData(), 0),
        );
    }

    // Fill the last frame.
    const last_pid = bpm.newPage();
    var last_page = (try bpm.getReadPage(last_pid)).?;
    defer last_page.drop() catch unreachable;

    try std.testing.expect((try bpm.getReadPage(pid0)) == null);
}

test "bustub::PageAccessTest" {
    const rounds = 50;

    const cwd = try std.process.currentPathAlloc(io, gpa);
    const testDbPath = try std.fs.path.resolve(gpa, &.{ cwd, "./test.db" });
    var dm: DiskManager = try .init(gpa, io, testDbPath);
    const bpm = try BufferPoolManager.init(gpa, io, 1, &dm);

    defer gpa.free(cwd);
    defer gpa.free(testDbPath);
    defer dm.deinit();
    defer bpm.deinit();
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), io, testDbPath) catch unreachable;

    const pid = bpm.newPage();
    var buf: [pageSize]u8 = undefined;

    const writer = try std.Thread.spawn(.{}, struct {
        fn run(_bpm: *BufferPoolManager, _pid: PageId) !void {
            var tmp: [32]u8 = undefined;

            for (0..rounds) |i| {
                try std.Io.sleep(io, .fromMilliseconds(5), .awake);

                var guard = (try _bpm.getWritePage(_pid)).?;
                defer guard.drop() catch unreachable;

                const s = try std.fmt.bufPrint(&tmp, "{d}", .{i});
                @memcpy(guard.getDataMut()[0..s.len], s);
            }
        }
    }.run, .{ bpm, pid });

    defer writer.join();

    for (0..rounds) |_| {
        try std.Io.sleep(io, .fromMilliseconds(10), .awake);

        var guard = (try bpm.getReadPage(pid)).?;
        defer guard.drop() catch unreachable;

        @memcpy(&buf, guard.getData());

        try std.Io.sleep(io, .fromMilliseconds(10), .awake);

        try std.testing.expectEqualSlices(
            u8,
            &buf,
            guard.getData(),
        );
    }
}

test "bustub::ContentionTest" {
    const rounds = 100_000;

    const cwd = try std.process.currentPathAlloc(io, gpa);
    const testDbPath = try std.fs.path.resolve(gpa, &.{ cwd, "./test.db" });
    var dm: DiskManager = try .init(gpa, io, testDbPath);
    const bpm = try BufferPoolManager.init(gpa, io, FRAMES, &dm);

    defer gpa.free(cwd);
    defer gpa.free(testDbPath);
    defer dm.deinit();
    defer bpm.deinit();
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), io, testDbPath) catch unreachable;

    const pid = bpm.newPage();

    const Writer = struct {
        fn run(_bpm: *BufferPoolManager, _pid: PageId) !void {
            var tmp: [32]u8 = undefined;

            for (0..rounds) |i| {
                var guard = (try _bpm.getWritePage(_pid)).?;
                defer guard.drop() catch unreachable;

                const s = try std.fmt.bufPrint(&tmp, "{d}", .{i});
                const data = guard.getDataMut();
                @memcpy(data[0..s.len], s);
                data[s.len] = 0;
            }
        }
    };

    const thread1 = try std.Thread.spawn(.{}, Writer.run, .{ bpm, pid });
    const thread2 = try std.Thread.spawn(.{}, Writer.run, .{ bpm, pid });
    const thread3 = try std.Thread.spawn(.{}, Writer.run, .{ bpm, pid });
    const thread4 = try std.Thread.spawn(.{}, Writer.run, .{ bpm, pid });

    thread3.join();
    thread2.join();
    thread4.join();
    thread1.join();
}

test "bustub::DeadlockTest" {
    const cwd = try std.process.currentPathAlloc(io, gpa);
    const testDbPath = try std.fs.path.resolve(gpa, &.{ cwd, "./test.db" });
    var dm: DiskManager = try .init(gpa, io, testDbPath);
    const bpm = try BufferPoolManager.init(gpa, io, FRAMES, &dm);

    defer gpa.free(cwd);
    defer gpa.free(testDbPath);
    defer dm.deinit();
    defer bpm.deinit();
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), io, testDbPath) catch unreachable;

    const pid0 = bpm.newPage();
    const pid1 = bpm.newPage();

    var guard0 = (try bpm.getWritePage(pid0)).?;

    var start = std.atomic.Value(bool).init(false);

    const child = try std.Thread.spawn(.{}, struct {
        fn run(
            _bpm: *BufferPoolManager,
            _pid0: PageId,
            _start: *std.atomic.Value(bool),
        ) !void {
            _start.store(true, .release);

            var child_guard = (try _bpm.getWritePage(_pid0)).?;
            defer child_guard.drop() catch unreachable;
        }
    }.run, .{ bpm, pid0, &start });

    defer child.join();

    while (!start.load(.acquire)) {
        std.Thread.yield() catch {};
    }

    try std.Io.sleep(io, .fromSeconds(1), .awake);

    var guard1 = (try bpm.getWritePage(pid1)).?;
    defer guard1.drop() catch unreachable;

    guard0.drop() catch unreachable;
}

test "bustub::EvictableTest" {
    const rounds = 1000;
    const num_readers = 8;

    const cwd = try std.process.currentPathAlloc(io, gpa);
    const testDbPath = try std.fs.path.resolve(gpa, &.{ cwd, "./test.db" });
    var dm: DiskManager = try .init(gpa, io, testDbPath);
    const bpm = try BufferPoolManager.init(gpa, io, 1, &dm);

    defer gpa.free(cwd);
    defer gpa.free(testDbPath);
    defer dm.deinit();
    defer bpm.deinit();
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), io, testDbPath) catch unreachable;

    for (0..rounds) |i| {
        var mutex: std.Io.Mutex = .init;
        var cv: std.Io.Condition = .init;
        var signal = false;

        const winner_pid = bpm.newPage();
        const loser_pid = bpm.newPage();

        var readers = std.ArrayList(std.Thread).empty;
        defer {
            for (readers.items) |thread| {
                thread.join();
            }
            readers.deinit(gpa);
        }

        for (0..num_readers) |_| {
            const thread = try std.Thread.spawn(.{}, struct {
                fn run(
                    _io: std.Io,
                    _bpm: *BufferPoolManager,
                    _mutex: *std.Io.Mutex,
                    _cv: *std.Io.Condition,
                    _signal: *bool,
                    _winner_pid: PageId,
                    _loser_pid: PageId,
                ) !void {
                    _mutex.lockUncancelable(_io);
                    defer _mutex.unlock(_io);

                    while (!_signal.*) {
                        _cv.waitUncancelable(_io, _mutex);
                    }

                    _mutex.unlock(_io);
                    defer _mutex.lockUncancelable(_io);

                    var read_guard = (try _bpm.getReadPage(_winner_pid)).?;
                    defer read_guard.drop() catch unreachable;

                    try std.testing.expect(
                        (try _bpm.getReadPage(_loser_pid)) == null,
                    );
                }
            }.run, .{
                io,
                bpm,
                &mutex,
                &cv,
                &signal,
                winner_pid,
                loser_pid,
            });

            try readers.append(gpa, thread);
        }

        mutex.lockUncancelable(io);

        if (i % 2 == 0) {
            var read_guard = (try bpm.getReadPage(winner_pid)).?;

            signal = true;
            cv.broadcast(io);

            mutex.unlock(io);

            read_guard.drop() catch unreachable;
        } else {
            var write_guard = (try bpm.getWritePage(winner_pid)).?;

            signal = true;
            cv.broadcast(io);

            mutex.unlock(io);

            write_guard.drop() catch unreachable;
        }
    }
}
