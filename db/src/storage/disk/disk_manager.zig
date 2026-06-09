const std = @import("std");
const page = @import("../page/page.zig");

pub const DiskManager = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    file: std.Io.File,
    pages: std.AutoHashMap(usize, usize),
    pageCapacity: usize,
    freeSlots: std.ArrayList(usize),
    buf: [page.size]u8,

    pub fn init(gpa: std.mem.Allocator, io: std.Io, dbFilePath: []const u8) !DiskManager {
        const file = std.Io.Dir.openFileAbsolute(io, dbFilePath, .{ .mode = .read_write }) catch |err| switch (err) {
            error.FileNotFound => blk: {
                const new = try std.Io.Dir.createFileAbsolute(io, dbFilePath, .{});
                try new.setLength(io, (initNumPagesInFile + 1) * page.size);
                break :blk new;
            },
            else => return err,
        };
        return .{ .gpa = gpa, .io = io, .file = file, .pages = .init(gpa), .pageCapacity = initNumPagesInFile, .freeSlots = .empty, .buf = undefined };
    }

    pub fn deinit(dm: *DiskManager) void {
        dm.freeSlots.deinit(dm.gpa);
        dm.pages.deinit();
        dm.file.close(dm.io);
    }

    pub fn writePage(dm: *DiskManager, pageId: usize, data: []const u8) !void {
        var writer = dm.file.writer(dm.io, &dm.buf);
        if (!dm.pages.contains(pageId)) {
            try dm.pages.put(pageId, try dm.allocatePage());
        }
        const offset = dm.pages.get(pageId).?;
        try writer.seekTo(offset);
        try writer.interface.writeAll(data);
        try writer.interface.flush();
    }

    fn allocatePage(dm: *DiskManager) !usize {
        if (dm.pages.count() + 1 > dm.pageCapacity) {
            dm.pageCapacity *= 2;
            try dm.file.setLength(dm.io, (dm.pageCapacity + 1) * page.size);
        }
        return (dm.pages.count() + 1) * page.size;
    }
};

const initNumPagesInFile = 16;
