const std = @import("std");
const testing = @import("std").testing;
const gpa = testing.allocator;
const io = testing.io;

const page = @import("./page.zig");
const DiskManager = @import("./disk_manager.zig").DiskManager;
const DiskScheduler = @import("./disk_scheduler.zig").DiskScheduler;
const DiskRequest = @import("./disk_scheduler.zig").DiskRequest;

test DiskScheduler {
    const cwd = try std.process.currentPathAlloc(testing.io, testing.allocator);
    const testDbPath = try std.fs.path.resolve(testing.allocator, &.{ cwd, "./test.db" });
    var dm: DiskManager = try .init(testing.allocator, testing.io, testDbPath);
    const ds: *DiskScheduler = try .init(testing.allocator, testing.io, &dm);
    defer testing.allocator.free(testDbPath);
    defer testing.allocator.free(cwd);
    defer dm.deinit();
    defer ds.deinit();
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, testDbPath) catch unreachable;

    var out: [page.size]u8 = undefined;
    const in = "hello, db";
    const write = try ds.scheduleWrite(0, in);
    const read = try ds.scheduleRead(0, &out);
    write.wait();
    read.wait();
    try std.testing.expectEqualSlices(u8, in, out[0..in.len]);

    write.destroy(gpa);
    read.destroy(gpa);
}
