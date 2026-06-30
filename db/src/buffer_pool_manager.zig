const std = @import("std");

const DiskManager = @import("disk_manager.zig").DiskManager;
const ArcReplacer = @import("arc_replacer.zig").ArcReplacer;
const DiskScheduler = @import("disk_scheduler.zig").DiskScheduler;
const DiskRequest = @import("disk_scheduler.zig").DiskRequest;
const page = @import("page.zig");

pub const BufferPoolManager = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    mu: std.Io.Mutex = .init,

    size: usize,
    nextPageId: usize = 0, // db is treated as brand new
    frames: std.ArrayList(Frame),
    freeFrames: std.DoublyLinkedList = .{},
    pageTable: std.AutoHashMap(usize, *Frame), // page id -> frame

    arc: ArcReplacer,
    dm: *DiskManager,
    ds: *DiskScheduler,

    pub fn init(
        gpa: std.mem.Allocator,
        io: std.Io,
        size: usize,
        diskManager: *DiskManager,
    ) !*BufferPoolManager {
        const self: *BufferPoolManager = try gpa.create(BufferPoolManager);
        self.* = .{
            .gpa = gpa,
            .io = io,
            .size = size,
            .frames = try .initCapacity(gpa, size),
            .pageTable = .init(gpa),
            .arc = .init(gpa, io, size),
            .dm = diskManager,
            .ds = try .init(gpa, io, diskManager),
        };

        // Init frames
        for (0..size) |i| {
            try self.frames.append(gpa, .{ .id = i, .bpm = self });
            self.freeFrames.append(&self.frames.items[i].node);
        }

        return self;
    }

    pub fn deinit(self: *BufferPoolManager) void {
        self.frames.deinit(self.gpa);
        self.pageTable.deinit();
        self.arc.deinit();
        self.ds.deinit();
        self.gpa.destroy(self);
    }

    pub fn newPage(self: *BufferPoolManager) usize {
        self.mu.lockUncancelable(self.io);
        defer self.mu.unlock(self.io);

        const newPageId = self.nextPageId;
        self.nextPageId += 1;
        return newPageId;
    }

    pub fn getReadPage(self: *BufferPoolManager, pageId: usize) !?ReadPage {
        if (try self.getPage(pageId)) |frame| {
            frame.pageLock.lockSharedUncancelable(self.io);
            return .{ .frame = frame };
        }
        return null;
    }

    pub fn getWritePage(self: *BufferPoolManager, pageId: usize) !?WritePage {
        if (try self.getPage(pageId)) |frame| {
            frame.pageLock.lockUncancelable(self.io);
            return .{ .readPage = .{ .frame = frame } };
        }
        return null;
    }

    fn getPage(self: *BufferPoolManager, pageId: usize) !?*Frame {
        self.mu.lockUncancelable(self.io);

        // Select a frame
        var frame: *Frame = undefined;
        var pagingIn: bool = true;
        if (self.pageTable.get(pageId)) |f| {
            // Page already in BPM
            frame = f;
            pagingIn = false;
        } else if (self.freeFrames.popFirst()) |node| {
            // A free frame is available
            frame = @fieldParentPtr("node", node);
            frame.reset(pageId);
        } else if (try self.arc.evict()) |frameId| {
            // Need to evict
            frame = &self.frames.items[frameId];
            _ = self.pageTable.remove(frame.pageId.?);

            if (frame.isDirty) try frame.flush();
            frame.reset(pageId);
        } else {
            // All frames are not evictable
            self.mu.unlock(self.io);
            return null;
        }

        frame.pin();

        try self.pageTable.put(pageId, frame);
        try self.arc.recordAccess(frame.id, pageId);
        try self.arc.setEvictable(frame.id, false);

        // Page in data if exists on disk.
        if (pagingIn and self.dm.exists(pageId)) {
            frame.pageLock.lockUncancelable(self.io);
            defer frame.pageLock.unlock(self.io);
            self.mu.unlock(self.io);
            const r = try self.ds.scheduleRead(pageId, &frame.data);
            defer r.destroy(self.gpa);
            r.wait();
        } else {
            self.mu.unlock(self.io);
        }
        return frame;
    }

    fn release(self: *BufferPoolManager, frame: *Frame) !void {
        self.mu.lockUncancelable(self.io);
        defer self.mu.unlock(self.io);

        frame.unpin();
        if (frame.pinCount == 0) {
            try self.arc.setEvictable(frame.id, true);
        }
    }

    pub fn getPinCount(self: *BufferPoolManager, pageId: usize) ?usize {
        self.mu.lockUncancelable(self.io);
        defer self.mu.unlock(self.io);

        if (self.pageTable.get(pageId)) |f| {
            return f.pinCount;
        }
        return null;
    }
};

const Frame = struct {
    mu: std.Io.Mutex = .init,
    pageLock: std.Io.RwLock = .init,

    id: usize,
    pageId: ?usize = null,
    data: [page.size]u8 = undefined,
    isDirty: bool = false,
    pinCount: usize = 0,

    bpm: *BufferPoolManager,
    node: Node = .{},

    pub fn reset(self: *Frame, pageId: usize) void {
        self.pageId = pageId;
        self.isDirty = false;
        self.pinCount = 0;
        @memset(&self.data, 0);
    }

    pub fn pin(self: *Frame) void {
        self.pinCount += 1;
    }

    pub fn unpin(self: *Frame) void {
        self.pinCount -= 1;
    }

    pub fn markDirty(self: *Frame) void {
        self.isDirty = true;
    }

    pub fn flush(self: *Frame) !void {
        self.mu.lockUncancelable(self.bpm.io);
        defer self.mu.unlock(self.bpm.io);

        if (!self.isDirty) return;

        const r = try self.bpm.ds.scheduleWrite(self.pageId.?, &self.data);
        defer r.destroy(self.bpm.gpa);
        r.wait();
        self.isDirty = false;
    }

    pub fn release(self: *Frame) !void {
        try self.bpm.release(self);
    }
};

pub const WritePage = struct {
    readPage: ReadPage,

    pub fn getPageId(self: *const WritePage) usize {
        return self.readPage.getPageId();
    }

    pub fn getData(self: *const WritePage) []const u8 {
        return self.readPage.getData();
    }

    pub fn getDataMut(self: *WritePage) []u8 {
        self.readPage.frame.markDirty();
        return &self.readPage.frame.data;
    }

    pub fn isDirty(self: *WritePage) bool {
        return self.readPage.isDirty();
    }

    pub fn flush(self: *WritePage) !void {
        try self.readPage.flush();
    }

    pub fn release(self: *WritePage) !void {
        if (self.readPage.released) return;
        try self.readPage.frame.release();
        self.readPage.released = true;
        self.readPage.frame.pageLock.unlock(self.readPage.frame.bpm.io);
    }
};

pub const ReadPage = struct {
    frame: *Frame,
    released: bool = false,

    pub fn getPageId(self: *const ReadPage) usize {
        return self.frame.pageId.?;
    }

    pub fn getData(self: *const ReadPage) []const u8 {
        return &self.frame.data;
    }

    pub fn isDirty(self: *const ReadPage) bool {
        return self.frame.isDirty;
    }

    pub fn flush(self: *ReadPage) !void {
        try self.frame.flush();
    }

    pub fn release(self: *ReadPage) !void {
        if (self.released) return;
        try self.frame.release();
        self.released = true;
        self.frame.pageLock.unlockShared(self.frame.bpm.io);
    }
};

const Node = std.DoublyLinkedList.Node;
