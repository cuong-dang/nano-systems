const std = @import("std");

const PageId = @import("page.zig").PageId;
const Channel = @import("./channel.zig").Channel;
const DiskManager = @import("./disk_manager.zig").DiskManager;

pub const DiskScheduler = struct {
    gpa: std.mem.Allocator,
    io: std.Io,

    q: Channel(?*DiskRequest),
    worker: std.Thread,
    dm: *DiskManager,

    pub fn init(gpa: std.mem.Allocator, io: std.Io, dm: *DiskManager) !*DiskScheduler {
        const self = try gpa.create(DiskScheduler);
        self.* = .{ .gpa = gpa, .io = io, .q = .init(gpa, io), .worker = undefined, .dm = dm };
        self.worker = try .spawn(.{}, workerMain, .{ &self.q, self.dm });
        return self;
    }

    pub fn deinit(self: *DiskScheduler) void {
        self.q.put(null) catch {}; // OOM is ignored.
        self.worker.join();
        self.gpa.destroy(self);
    }

    pub fn scheduleRead(self: *DiskScheduler, pageId: PageId, out: []u8) !*DiskRequest {
        const request = try DiskRequest.createReadRequest(self.gpa, self.io, pageId, out);
        try self.schedule(&.{request});
        return request;
    }

    pub fn scheduleWrite(self: *DiskScheduler, pageId: PageId, in: []const u8) !*DiskRequest {
        const request = try DiskRequest.createWriteRequest(self.gpa, self.io, pageId, in);
        try self.schedule(&.{request});
        return request;
    }

    pub fn schedule(self: *DiskScheduler, requests: []const *DiskRequest) !void {
        for (requests) |request| {
            try self.q.put(request);
        }
    }
};

fn workerMain(q: *Channel(?*DiskRequest), dm: *DiskManager) void {
    while (true) {
        if (q.get()) |r| {
            var err: ?anyerror = null;
            if (r.isWrite) {
                dm.writePage(r.pageId, r.in) catch |e| {
                    err = e;
                };
            } else {
                dm.readPage(r.pageId, r.out) catch |e| {
                    err = e;
                };
            }
            r.markDone(if (err == null) true else false, err);
        } else {
            return;
        }
    }
}

pub const DiskRequest = struct {
    io: std.Io,
    mu: std.Io.Mutex = .init,
    cond: std.Io.Condition = .init,

    isWrite: bool,
    pageId: PageId,
    in: []const u8 = undefined,
    out: []u8 = undefined,
    ok: ?bool = null,
    err: ?anyerror = null,

    pub fn createReadRequest(gpa: std.mem.Allocator, io: std.Io, pageId: PageId, out: []u8) !*DiskRequest {
        const r = try gpa.create(DiskRequest);
        r.* = .{ .io = io, .isWrite = false, .pageId = pageId, .out = out };
        return r;
    }

    pub fn createWriteRequest(gpa: std.mem.Allocator, io: std.Io, pageId: PageId, in: []const u8) !*DiskRequest {
        const r = try gpa.create(DiskRequest);
        r.* = .{ .io = io, .isWrite = true, .pageId = pageId, .in = in };
        return r;
    }

    pub fn destroy(self: *DiskRequest, gpa: std.mem.Allocator) void {
        gpa.destroy(self);
    }

    pub fn wait(self: *DiskRequest) void {
        self.mu.lockUncancelable(self.io);
        defer self.mu.unlock(self.io);

        // Block only if the request hasn't been marked done yet
        while (self.ok == null) {
            self.cond.waitUncancelable(self.io, &self.mu);
        }
    }

    pub fn markDone(self: *DiskRequest, ok: bool, err: ?anyerror) void {
        self.mu.lockUncancelable(self.io);
        defer self.mu.unlock(self.io);
        self.ok = ok;
        self.err = err;
        self.cond.broadcast(self.io);
    }
};
