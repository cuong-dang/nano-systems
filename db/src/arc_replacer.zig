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
        }
        // In MFU
        if (self.inMfu.get(frameId)) |node| {
            self.mfu.remove(node);
            self.mfu.prepend(node);
        }

        // In MRU Ghost
        if (self.inMruGhost.get(pageId)) |node| {
            if (mruGhostLen >= mfuGhostLen) self.mruTargetSize += 1 else self.mruTargetSize += mfuGhostLen / mruGhostLen;
            if (self.mruTargetSize > self.size) self.mruTargetSize = self.size;

            self.mfu.prepend(node);
            try self.inMfu.put(frameId, node);
            self.mruGhost.remove(node);
            _ = self.inMruGhost.remove(pageId);
            return;
        }
        // In MFU Ghost
        if (self.inMfuGhost.get(pageId)) |node| {
            if (mfuGhostLen >= mruGhostLen) self.mruTargetSize -|= 1 else self.mruTargetSize -|= mruGhostLen / mfuGhostLen;

            self.mfu.prepend(node);
            try self.inMfu.put(frameId, node);
            self.mfuGhost.remove(node);
            _ = self.inMfuGhost.remove(pageId);
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
        try self.inMru.put(pageId, &frame.node);
    }
};

const Frame = struct {
    frameId: FrameId,
    pageId: PageId,
    evictable: bool = true,
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
    gpa.destroy(frame);
    _ = lookup.remove(frame.pageId);
}
