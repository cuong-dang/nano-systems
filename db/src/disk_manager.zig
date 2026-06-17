const std = @import("std");
const page = @import("./page.zig");

pub const DiskManager = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    mu: std.Io.Mutex = .init,

    file: std.Io.File,
    pages: std.AutoHashMap(usize, usize),
    pageCapacity: usize = initPageCapacity,
    freeSlots: std.ArrayList(usize) = .empty,
    buf: [page.size]u8 = undefined,

    pub fn init(gpa: std.mem.Allocator, io: std.Io, dbFilePath: []const u8) !DiskManager {
        const file = std.Io.Dir.openFileAbsolute(io, dbFilePath, .{ .mode = .read_write }) catch |err| switch (err) {
            error.FileNotFound => blk: {
                const new = try std.Io.Dir.createFileAbsolute(io, dbFilePath, .{ .read = true });
                try new.setLength(io, initPageCapacity * page.size);
                break :blk new;
            },
            else => return err,
        };
        return .{ .gpa = gpa, .io = io, .file = file, .pages = .init(gpa) };
    }

    pub fn deinit(dm: *DiskManager) void {
        dm.freeSlots.deinit(dm.gpa);
        dm.pages.deinit();
        dm.file.close(dm.io);
    }

    pub fn readPage(dm: *DiskManager, pageId: usize, out: []u8) !void {
        try dm.mu.lock(dm.io);
        defer dm.mu.unlock(dm.io);

        if (!dm.pages.contains(pageId)) return Error.PageNotFound;

        var reader = dm.file.reader(dm.io, &dm.buf);
        const offset = dm.pages.get(pageId).?;
        try reader.seekTo(offset);
        try reader.interface.readSliceAll(out);
    }

    pub fn writePage(dm: *DiskManager, pageId: usize, data: []const u8) !void {
        try dm.mu.lock(dm.io);
        defer dm.mu.unlock(dm.io);

        if (!dm.pages.contains(pageId)) {
            try dm.pages.put(pageId, try dm.allocatePage());
        }

        var writer = dm.file.writer(dm.io, &dm.buf);
        const offset = dm.pages.get(pageId).?;
        try writer.seekTo(offset);
        try writer.interface.writeAll(data);
        try writer.interface.flush();
    }

    fn allocatePage(dm: *DiskManager) !usize {
        if (dm.pages.count() + 1 > dm.pageCapacity) {
            dm.pageCapacity *= 2;
            try dm.file.setLength(dm.io, dm.pageCapacity * page.size);
        }
        return dm.pages.count() * page.size;
    }
};

pub const initPageCapacity = 16;

const Error = error{PageNotFound};
