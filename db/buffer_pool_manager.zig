const std = @import("std");

const DiskManager = @import("disk_manager.zig").DiskManager;
const ArcReplacer = @import("arc_replacer.zig").ArcReplacer;
const DiskScheduler = @import("disk_scheduler.zig").DiskScheduler;
const DiskRequest = @import("disk_scheduler.zig").DiskRequest;
const page = @import("page.zig");
const PageId = @import("page.zig").PageId;

pub const BufferPoolManager = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    mu: std.Io.Mutex = .init,

    size: usize,
    nextPageId: PageId = 0, // db is treated as brand new
    frames: std.ArrayList(Frame),
    freeFrames: std.DoublyLinkedList = .{},
    pageTable: std.AutoHashMap(PageId, *Frame), // page id -> frame

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

    pub fn newPage(self: *BufferPoolManager) PageId {
        self.mu.lockUncancelable(self.io);
        defer self.mu.unlock(self.io);

        const newPageId = self.nextPageId;
        self.nextPageId += 1;
        return newPageId;
    }

    pub fn getReadPage(self: *BufferPoolManager, pageId: PageId) !?ReadPage {
        if (try self.getPage(pageId)) |frame| {
            frame.pageLock.lockSharedUncancelable(self.io);
            return .{ .frame = frame };
        }
        return null;
    }

    pub fn getWritePage(self: *BufferPoolManager, pageId: PageId) !?WritePage {
        if (try self.getPage(pageId)) |frame| {
            frame.pageLock.lockUncancelable(self.io);
            return .{ .readPage = .{ .frame = frame } };
        }
        return null;
    }

    fn getPage(self: *BufferPoolManager, pageId: PageId) !?*Frame {
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
        self.arc.setEvictable(frame.id, false);

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

    fn drop(self: *BufferPoolManager, frame: *Frame) void {
        self.mu.lockUncancelable(self.io);
        defer self.mu.unlock(self.io);

        frame.unpin();
        if (frame.pinCount == 0) {
            self.arc.setEvictable(frame.id, true);
        }
    }

    pub fn getPinCount(self: *BufferPoolManager, pageId: PageId) ?usize {
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
    pageId: ?PageId = null,
    data: [page.size]u8 align(@alignOf(std.c.max_align_t)) = undefined,
    isDirty: bool = false,
    pinCount: usize = 0,

    bpm: *BufferPoolManager,
    node: Node = .{},

    pub fn reset(self: *Frame, pageId: PageId) void {
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

    pub fn drop(self: *Frame) void {
        self.bpm.drop(self);
    }
};

pub const WritePage = struct {
    readPage: ReadPage,

    pub fn getPageId(self: *const WritePage) PageId {
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

    pub fn drop(self: *WritePage) void {
        if (self.readPage.dropped) return;
        self.readPage.frame.drop();
        self.readPage.dropped = true;
        self.readPage.frame.pageLock.unlock(self.readPage.frame.bpm.io);
    }
};

pub const ReadPage = struct {
    frame: *Frame,
    dropped: bool = false,

    pub fn getPageId(self: *const ReadPage) PageId {
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

    pub fn drop(self: *ReadPage) void {
        if (self.dropped) return;
        self.frame.drop();
        self.dropped = true;
        self.frame.pageLock.unlockShared(self.frame.bpm.io);
    }
};

const Node = std.DoublyLinkedList.Node;
