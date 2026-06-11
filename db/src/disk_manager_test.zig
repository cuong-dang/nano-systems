const std = @import("std");

const page = @import("./page.zig");
const DiskManager = @import("./disk_manager.zig").DiskManager;

test "writes and reads pages" {
    const cwd = try std.process.currentPathAlloc(std.testing.io, std.testing.allocator);
    const testDbPath = try std.fs.path.resolve(std.testing.allocator, &.{ cwd, "./test.db" });
    var dm: DiskManager = try .init(std.testing.allocator, std.testing.io, testDbPath);
    defer std.testing.allocator.free(cwd);
    defer std.testing.allocator.free(testDbPath);
    defer dm.deinit();
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, testDbPath) catch unreachable;

    try std.testing.expectEqual(dm.pageCapacity, 16);

    const data = "hello, db";
    try dm.writePage(100, data);
    var out: [page.size]u8 = undefined;
    try dm.readPage(100, &out);
    try std.testing.expectEqualSlices(u8, data, out[0..data.len]);

    const data2 = "hello again, db";
    try dm.writePage(101, data2);
    try dm.readPage(101, &out);
    try std.testing.expectEqualSlices(u8, data2, out[0..data2.len]);
}

test "grows" {
    const cwd = try std.process.currentPathAlloc(std.testing.io, std.testing.allocator);
    const testDbPath = try std.fs.path.resolve(std.testing.allocator, &.{ cwd, "./test.db" });
    var dm: DiskManager = try .init(std.testing.allocator, std.testing.io, testDbPath);
    defer std.testing.allocator.free(cwd);
    defer std.testing.allocator.free(testDbPath);
    defer dm.deinit();
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, testDbPath) catch unreachable;

    for (100..117) |i| {
        try dm.writePage(i, &.{});
    }
    try std.testing.expectEqual(dm.pageCapacity, 32);
}
