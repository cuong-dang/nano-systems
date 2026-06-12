const std = @import("std");

pub const ArcReplacer = struct {
    gpa: std.mem.Allocator,

    size: usize,
    numEvictable: usize = 0,
    mruTargetSize: usize = 0,

    mru: std.DoublyLinkedList = .{},
    mfu: std.DoublyLinkedList = .{},
    inMru: std.AutoHashMap(FrameId, *std.DoublyLinkedList.Node),
    inMfu: std.AutoHashMap(FrameId, *std.DoublyLinkedList.Node),

    mruGhost: std.DoublyLinkedList = .{},
    mfuGhost: std.DoublyLinkedList = .{},
    inMruGhost: std.AutoHashMap(PageId, *std.DoublyLinkedList.Node),
    inMfuGhost: std.AutoHashMap(PageId, *std.DoublyLinkedList.Node),

    pub fn init(gpa: std.mem.Allocator, size: usize) ArcReplacer {
        return .{ .gpa = gpa, .size = size, .inMru = .init(gpa), .inMfu = .init(gpa), .inMruGhost = .init(gpa), .inMfuGhost = .init(gpa) };
    }

    pub fn deinit(self: *ArcReplacer) void {
        self.inMru.deinit();
        self.inMfu.deinit();
        self.inMruGhost.deinit();
        self.inMfuGhost.deinit();
    }

    pub fn recordAccess(self: *ArcReplacer, frameId: FrameId, pageId: PageId) !void {
        const mruGhostLen = self.mruGhost.len();
        const mfuGhostLen = self.mfuGhost.len();

        // In MRU
        if (self.inMru.get(frameId)) |node| {
            self.mru.remove(node);
            _ = self.inMru.remove(frameId);
            self.mfu.prepend(node);
            try self.inMfu.put(frameId, node);
            return;
        }
        // In MFU
        if (self.inMfu.get(frameId)) |node| {
            self.mfu.remove(node);
            self.mfu.prepend(node);
            return;
        }

        // In MRU Ghost
        if (self.inMruGhost.get(pageId)) |node| {
            if (mruGhostLen >= mfuGhostLen) self.mruTargetSize += 1 else self.mruTargetSize += mfuGhostLen / mruGhostLen;
            if (self.mruTargetSize > self.size) self.mruTargetSize = self.size;

            self.mruGhost.remove(node);
            _ = self.inMruGhost.remove(pageId);
            self.mfu.prepend(node);
            try self.inMfu.put(frameId, node);
            return;
        }
        // In MFU Ghost
        if (self.inMfuGhost.get(pageId)) |node| {
            if (mfuGhostLen >= mruGhostLen) self.mruTargetSize -|= 1 else self.mruTargetSize -|= mruGhostLen / mfuGhostLen;

            self.mfuGhost.remove(node);
            _ = self.inMfuGhost.remove(pageId);
            self.mfu.prepend(node);
            try self.inMfu.put(frameId, node);
            return;
        }
        // Not in the replacer
        if (self.mru.len() + mruGhostLen == self.size) {
            killLast(self.gpa, &self.mruGhost, &self.inMruGhost);
        } else {
            std.debug.assert(self.mru.len() + mruGhostLen < self.size);
            if (self.mru.len() + mruGhostLen + self.mfu.len() + mfuGhostLen == 2 * self.size) {
                killLast(self.gpa, &self.mfuGhost, &self.inMfuGhost);
            }
        }
        const frame = try Frame.create(self.gpa, frameId, pageId);
        self.mru.prepend(&frame.node);
        try self.inMru.put(frameId, &frame.node);
    }

    pub fn setEvictable(self: *ArcReplacer, frameId: FrameId, evictable: bool) !void {
        const node = self.inMru.get(frameId) orelse self.inMfu.get(frameId) orelse return Error.FrameNotFound;
        var frame: *Frame = @fieldParentPtr("node", node);
        if (!frame.evictable and evictable) self.numEvictable += 1 else if (frame.evictable and !evictable) self.numEvictable -= 1;
        frame.evictable = evictable;
    }

    pub fn evict(self: *ArcReplacer) !?FrameId {
        if (self.mru.len() < self.mruTargetSize) {
            return try self.evictFromMfu() orelse try self.evictFromMru();
        }
        return try self.evictFromMru() orelse try self.evictFromMfu();
    }

    fn evictFromMru(self: *ArcReplacer) !?FrameId {
        var it = self.mru.last;
        while (it) |node| : (it = node.prev) {
            const frame: *Frame = @fieldParentPtr("node", node);
            if (frame.evictable) {
                self.mru.remove(node);
                _ = self.inMru.remove(frame.frameId);

                self.numEvictable -= 1;
                frame.evictable = false; // reset before moving into ghost list

                self.mruGhost.prepend(node);
                try self.inMruGhost.put(frame.pageId, node);
                return frame.frameId;
            }
        }
        return null;
    }

    fn evictFromMfu(self: *ArcReplacer) !?FrameId {
        var it = self.mfu.last;
        while (it) |node| : (it = node.prev) {
            const frame: *Frame = @fieldParentPtr("node", node);
            if (frame.evictable) {
                self.mfu.remove(node);
                _ = self.inMfu.remove(frame.frameId);

                self.numEvictable -= 1;
                frame.evictable = false; // reset before moving into ghost list

                self.mfuGhost.prepend(node);
                try self.inMfuGhost.put(frame.pageId, node);
                return frame.frameId;
            }
        }
        return null;
    }
};

const Frame = struct {
    frameId: FrameId,
    pageId: PageId,
    evictable: bool = false,
    node: std.DoublyLinkedList.Node,

    pub fn create(gpa: std.mem.Allocator, frameId: FrameId, pageId: PageId) !*Frame {
        const new = try gpa.create(Frame);
        new.* = .{ .frameId = frameId, .pageId = pageId, .node = .{} };
        return new;
    }
};

const FrameId = usize;
const PageId = usize;

fn killLast(gpa: std.mem.Allocator, list: *std.DoublyLinkedList, lookup: *std.AutoHashMap(PageId, *std.DoublyLinkedList.Node)) void {
    std.debug.assert(list.len() > 0);
    const last = list.last.?;
    const frame: *Frame = @fieldParentPtr("node", last);
    list.remove(last);
    _ = lookup.remove(frame.pageId);
    gpa.destroy(frame);
}

const Error = error{FrameNotFound};
