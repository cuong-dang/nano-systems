const std = @import("std");
const Node = std.DoublyLinkedList.Node;

pub const ArcReplacer = struct {
    gpa: std.mem.Allocator,

    size: usize,
    numEvictable: usize = 0,
    mruTargetSize: usize = 0,

    mru: std.DoublyLinkedList = .{},
    mfu: std.DoublyLinkedList = .{},
    mruLen: usize = 0,
    mfuLen: usize = 0,
    inMru: std.AutoHashMap(FrameId, *Node),
    inMfu: std.AutoHashMap(FrameId, *Node),

    mruGhost: std.DoublyLinkedList = .{},
    mfuGhost: std.DoublyLinkedList = .{},
    mruGhostLen: usize = 0,
    mfuGhostLen: usize = 0,
    inMruGhost: std.AutoHashMap(PageId, *Node),
    inMfuGhost: std.AutoHashMap(PageId, *Node),

    pub fn init(gpa: std.mem.Allocator, size: usize) ArcReplacer {
        return .{ .gpa = gpa, .size = size, .inMru = .init(gpa), .inMfu = .init(gpa), .inMruGhost = .init(gpa), .inMfuGhost = .init(gpa) };
    }

    pub fn deinit(self: *ArcReplacer) void {
        // Destroy frames
        destroyFrames(self.gpa, &self.mru);
        destroyFrames(self.gpa, &self.mfu);
        destroyFrames(self.gpa, &self.mruGhost);
        destroyFrames(self.gpa, &self.mfuGhost);

        self.inMru.deinit();
        self.inMfu.deinit();
        self.inMruGhost.deinit();
        self.inMfuGhost.deinit();
    }

    pub fn recordAccess(self: *ArcReplacer, frameId: FrameId, pageId: PageId) !void {

        // In MRU
        if (self.inMru.get(frameId)) |node| {
            std.debug.print("CASE 1\n", .{});
            self.mruRemove(frameId, node);
            try self.mfuPrepend(frameId, node);
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
            if (self.mruGhostLen >= self.mfuGhostLen) self.mruTargetSize += 1 else self.mruTargetSize += self.mfuGhostLen / self.mruGhostLen;
            if (self.mruTargetSize > self.size) self.mruTargetSize = self.size;

            self.mruGhostRemove(pageId, node);
            try self.mfuPrepend(frameId, node);
            return;
        }
        // In MFU Ghost
        if (self.inMfuGhost.get(pageId)) |node| {
            if (self.mfuGhostLen >= self.mruGhostLen) self.mruTargetSize -|= 1 else self.mruTargetSize -|= self.mruGhostLen / self.mfuGhostLen;

            self.mfuGhostRemove(pageId, node);
            try self.mfuPrepend(frameId, node);
            return;
        }
        // Not in the replacer
        if (self.mru.len() + self.mruGhostLen == self.size) {
            self.mruGhostKillLast();
        } else {
            std.debug.assert(self.mru.len() + self.mruGhostLen < self.size);
            if (self.mru.len() + self.mruGhostLen + self.mfu.len() + self.mfuGhostLen == 2 * self.size) {
                self.mfuGhostKillLast();
            }
        }
        const frame = try Frame.create(self.gpa, frameId, pageId);
        try self.mruPrepend(frameId, &frame.node);
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

    pub fn print(self: *const ArcReplacer) void {
        // Format from bustub.

        // MRU Ghost
        std.debug.print("[", .{});
        var it = self.mruGhost.last;
        while (it) |node| : (it = it.?.prev) {
            const frame: *Frame = @fieldParentPtr("node", node);
            std.debug.print("({},_)", .{frame.pageId});
            if (it.?.prev != null) std.debug.print(", ", .{});
        }
        std.debug.print("]", .{});
        // MRU
        std.debug.print("[", .{});
        it = self.mru.last;
        while (it) |node| : (it = it.?.prev) {
            const frame: *Frame = @fieldParentPtr("node", node);
            std.debug.print("({},f{})", .{ frame.pageId, frame.frameId });
            if (it.?.prev != null) std.debug.print(", ", .{});
        }
        std.debug.print("]!", .{});
        // MFU
        std.debug.print("[", .{});
        it = self.mfu.first;
        while (it) |node| : (it = it.?.next) {
            const frame: *Frame = @fieldParentPtr("node", node);
            std.debug.print("({},f{})", .{ frame.pageId, frame.frameId });
            if (it.?.next != null) std.debug.print(", ", .{});
        }
        std.debug.print("]", .{});
        // MFU Ghost
        std.debug.print("[", .{});
        it = self.mfuGhost.first;
        while (it) |node| : (it = it.?.next) {
            const frame: *Frame = @fieldParentPtr("node", node);
            std.debug.print("({},_)", .{frame.pageId});
            if (it.?.next != null) std.debug.print(", ", .{});
        }
        std.debug.print("]", .{});

        // MRU target size
        std.debug.print(" p={}\n", .{self.mruTargetSize});
    }

    fn evictFromMru(self: *ArcReplacer) !?FrameId {
        var it = self.mru.last;
        while (it) |node| : (it = node.prev) {
            const frame: *Frame = @fieldParentPtr("node", node);
            if (frame.evictable) {
                self.mruRemove(frame.frameId, node);

                self.numEvictable -= 1;
                frame.evictable = false; // reset before moving into ghost list

                try self.mruGhostPrepend(frame.pageId, node);
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
                self.mfuRemove(frame.frameId, node);

                self.numEvictable -= 1;
                frame.evictable = false; // reset before moving into ghost list

                try self.mfuGhostPrepend(frame.pageId, node);
                return frame.frameId;
            }
        }
        return null;
    }

    fn mruPrepend(self: *ArcReplacer, frameId: FrameId, node: *Node) !void {
        // Needs to reset frameId here because we might move from ghost lists.
        const frame: *Frame = @fieldParentPtr("node", node);
        frame.resetFrameId(frameId);

        self.mru.prepend(node);
        self.mruLen += 1;
        try self.inMru.put(frameId, node);
    }

    fn mfuPrepend(self: *ArcReplacer, frameId: FrameId, node: *Node) !void {
        // Needs to reset frameId here because we might move from ghost lists.
        const frame: *Frame = @fieldParentPtr("node", node);
        frame.resetFrameId(frameId);

        self.mfu.prepend(node);
        self.mfuLen += 1;
        try self.inMfu.put(frameId, node);
    }

    fn mruRemove(self: *ArcReplacer, frameId: FrameId, node: *Node) void {
        self.mru.remove(node);
        self.mruLen -= 1;
        _ = self.inMru.remove(frameId);
    }

    fn mfuRemove(self: *ArcReplacer, frameId: FrameId, node: *Node) void {
        self.mfu.remove(node);
        self.mfuLen -= 1;
        _ = self.inMfu.remove(frameId);
    }

    fn mruGhostPrepend(self: *ArcReplacer, pageId: PageId, node: *Node) !void {
        self.mruGhost.prepend(node);
        self.mruGhostLen += 1;
        try self.inMruGhost.put(pageId, node);
    }

    fn mfuGhostPrepend(self: *ArcReplacer, pageId: PageId, node: *Node) !void {
        self.mfuGhost.prepend(node);
        self.mfuGhostLen += 1;
        try self.inMfuGhost.put(pageId, node);
    }

    fn mruGhostRemove(self: *ArcReplacer, pageId: PageId, node: *Node) void {
        self.mruGhost.remove(node);
        self.mruGhostLen -= 1;
        _ = self.inMruGhost.remove(pageId);
    }

    fn mfuGhostRemove(self: *ArcReplacer, pageId: PageId, node: *Node) void {
        self.mfuGhost.remove(node);
        self.mfuGhostLen -= 1;
        _ = self.inMfuGhost.remove(pageId);
    }

    fn mruGhostKillLast(self: *ArcReplacer) void {
        killLast(self.gpa, &self.mruGhost, &self.inMruGhost);
        self.mruGhostLen -= 1;
    }

    fn mfuGhostKillLast(self: *ArcReplacer) void {
        killLast(self.gpa, &self.mfuGhost, &self.inMfuGhost);
        self.mfuGhostLen -= 1;
    }
};

const Frame = struct {
    frameId: FrameId,
    pageId: PageId,
    evictable: bool = false,
    node: Node,

    pub fn create(gpa: std.mem.Allocator, frameId: FrameId, pageId: PageId) !*Frame {
        const new = try gpa.create(Frame);
        new.* = .{ .frameId = frameId, .pageId = pageId, .node = .{} };
        return new;
    }

    pub fn resetFrameId(self: *Frame, frameId: FrameId) void {
        self.frameId = frameId;
        self.evictable = false;
        // pageId stays the same.
    }
};

const FrameId = usize;
const PageId = usize;

fn killLast(gpa: std.mem.Allocator, list: *std.DoublyLinkedList, lookup: *std.AutoHashMap(PageId, *Node)) void {
    std.debug.assert(list.len() > 0);
    const last = list.last.?;
    const frame: *Frame = @fieldParentPtr("node", last);
    list.remove(last);
    _ = lookup.remove(frame.pageId);
    gpa.destroy(frame);
}

fn destroyFrames(gpa: std.mem.Allocator, list: *std.DoublyLinkedList) void {
    var it = list.first;
    while (it) |node| {
        it = node.next;
        const frame: *Frame = @fieldParentPtr("node", node);
        gpa.destroy(frame);
    }
}

const Error = error{FrameNotFound};
