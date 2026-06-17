const std = @import("std");
const Node = std.DoublyLinkedList.Node;

pub const ArcReplacer = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    mu: std.Io.Mutex = .init,

    size: usize,
    numEvictable: usize = 0,
    mruTargetSize: usize = 0,

    mru: List,
    mfu: List,
    mruGhost: List,
    mfuGhost: List,

    pub fn init(gpa: std.mem.Allocator, io: std.Io, size: usize) ArcReplacer {
        return .{ .gpa = gpa, .io = io, .size = size, .mru = .init(gpa), .mfu = .init(gpa), .mruGhost = .init(gpa), .mfuGhost = .init(gpa) };
    }

    pub fn deinit(self: *ArcReplacer) void {
        self.destroyFrames(&self.mru);
        self.destroyFrames(&self.mfu);
        self.destroyFrames(&self.mruGhost);
        self.destroyFrames(&self.mfuGhost);

        self.mru.deinit();
        self.mfu.deinit();
        self.mruGhost.deinit();
        self.mfuGhost.deinit();
    }

    pub fn recordAccess(self: *ArcReplacer, frameId: usize, pageId: usize) !void {
        try self.mu.lock(self.io);
        defer self.mu.unlock(self.io);

        // In MRU
        if (self.mru.get(frameId)) |node| {
            self.mru.remove(frameId, node);
            try self.mfu.prepend(frameId, node);
            return;
        }

        // In MFU
        if (self.mfu.get(frameId)) |node| {
            self.mfu.remove(frameId, node);
            try self.mfu.prepend(frameId, node);
            return;
        }

        // In MRU Ghost
        if (self.mruGhost.get(pageId)) |node| {
            if (self.mruGhost.len >= self.mfuGhost.len) self.mruTargetSize += 1 else self.mruTargetSize += self.mfuGhost.len / self.mruGhost.len;
            if (self.mruTargetSize > self.size) self.mruTargetSize = self.size;

            // Reset frame when moving from ghost lists.
            const frame: *Frame = @fieldParentPtr("node", node);
            frame.reset(frameId);

            self.mruGhost.remove(pageId, node);
            try self.mfu.prepend(frameId, node);
            return;
        }

        // In MFU Ghost
        if (self.mfuGhost.get(pageId)) |node| {
            if (self.mfuGhost.len >= self.mruGhost.len) self.mruTargetSize -|= 1 else self.mruTargetSize -|= self.mruGhost.len / self.mfuGhost.len;

            // Reset frame when moving from ghost lists.
            const frame: *Frame = @fieldParentPtr("node", node);
            frame.reset(frameId);

            self.mfuGhost.remove(pageId, node);
            try self.mfu.prepend(frameId, node);
            return;
        }

        // Not in the replacer
        if (self.mru.len + self.mruGhost.len == self.size) {
            self.killLast(&self.mruGhost);
        } else {
            if (self.mru.len + self.mruGhost.len + self.mfu.len + self.mfuGhost.len == 2 * self.size) {
                self.killLast(&self.mfuGhost);
            }
        }
        const frame = try Frame.create(self.gpa, frameId, pageId);
        try self.mru.prepend(frameId, &frame.node);
    }

    pub fn setEvictable(self: *ArcReplacer, frameId: usize, evictable: bool) !void {
        try self.mu.lock(self.io);
        defer self.mu.unlock(self.io);

        const node = self.mru.get(frameId) orelse self.mfu.get(frameId) orelse return Error.FrameNotFound;
        var frame: *Frame = @fieldParentPtr("node", node);
        if (!frame.evictable and evictable) self.numEvictable += 1 else if (frame.evictable and !evictable) self.numEvictable -= 1;
        frame.evictable = evictable;
    }

    pub fn evict(self: *ArcReplacer) !?usize {
        try self.mu.lock(self.io);
        defer self.mu.unlock(self.io);

        if (self.mru.len < self.mruTargetSize) {
            return try self.evictFrom(&self.mfu, &self.mfuGhost) orelse try self.evictFrom(&self.mru, &self.mruGhost);
        }
        return try self.evictFrom(&self.mru, &self.mruGhost) orelse try self.evictFrom(&self.mfu, &self.mfuGhost);
    }

    pub fn remove(self: *ArcReplacer, frameId: usize) !void {
        try self.mu.lock(self.io);
        defer self.mu.unlock(self.io);

        if (self.removeIfExists(frameId, &self.mru)) return;
        _ = self.removeIfExists(frameId, &self.mfu);
    }

    pub fn print(self: *ArcReplacer) !void {
        try self.mu.lock(self.io);
        defer self.mu.unlock(self.io);

        // Format from bustub.
        // MRU Ghost
        std.debug.print("[", .{});
        var it = self.mruGhost.list.last;
        while (it) |node| : (it = it.?.prev) {
            const frame: *Frame = @fieldParentPtr("node", node);
            std.debug.print("({},_)", .{frame.pageId});
            if (it.?.prev != null) std.debug.print(", ", .{});
        }
        std.debug.print("]", .{});
        // MRU
        std.debug.print("[", .{});
        it = self.mru.list.last;
        while (it) |node| : (it = it.?.prev) {
            const frame: *Frame = @fieldParentPtr("node", node);
            std.debug.print("({},f{})", .{ frame.pageId, frame.frameId });
            if (it.?.prev != null) std.debug.print(", ", .{});
        }
        std.debug.print("]!", .{});
        // MFU
        std.debug.print("[", .{});
        it = self.mfu.list.first;
        while (it) |node| : (it = it.?.next) {
            const frame: *Frame = @fieldParentPtr("node", node);
            std.debug.print("({},f{})", .{ frame.pageId, frame.frameId });
            if (it.?.next != null) std.debug.print(", ", .{});
        }
        std.debug.print("]", .{});
        // MFU Ghost
        std.debug.print("[", .{});
        it = self.mfuGhost.list.first;
        while (it) |node| : (it = it.?.next) {
            const frame: *Frame = @fieldParentPtr("node", node);
            std.debug.print("({},_)", .{frame.pageId});
            if (it.?.next != null) std.debug.print(", ", .{});
        }
        std.debug.print("]", .{});

        // MRU target size
        std.debug.print(" p={}\n", .{self.mruTargetSize});
    }

    fn killLast(self: *ArcReplacer, ghostList: *List) void {
        const last = ghostList.last().?;
        const frame: *Frame = @fieldParentPtr("node", last);
        ghostList.remove(frame.pageId, last);
        self.gpa.destroy(frame);
    }

    fn evictFrom(self: *ArcReplacer, list: *List, ghostList: *List) !?usize {
        var it = list.last();
        while (it) |node| : (it = node.prev) {
            const frame: *Frame = @fieldParentPtr("node", node);
            if (frame.evictable) {
                list.remove(frame.frameId, node);
                try ghostList.prepend(frame.pageId, node);
                self.numEvictable -= 1;
                return frame.frameId;
            }
        }
        return null;
    }

    fn removeIfExists(self: *ArcReplacer, frameId: usize, list: *List) bool {
        if (list.get(frameId)) |node| {
            const frame: *Frame = @fieldParentPtr("node", node);
            if (frame.evictable) {
                list.remove(frameId, node);
                self.gpa.destroy(frame);
                self.numEvictable -= 1;
                return true;
            }
        }
        return false;
    }

    fn destroyFrames(self: *ArcReplacer, list: *List) void {
        var it = list.last();
        while (it) |node| {
            it = node.prev;
            const frame: *Frame = @fieldParentPtr("node", node);
            self.gpa.destroy(frame);
        }
    }
};

const List = struct {
    list: std.DoublyLinkedList = .{},
    len: usize = 0,
    lookup: std.AutoHashMap(usize, *Node),

    pub fn init(gpa: std.mem.Allocator) List {
        return .{ .lookup = .init(gpa) };
    }

    pub fn deinit(self: *List) void {
        self.lookup.deinit();
    }

    pub fn get(self: *const List, id: usize) ?*Node {
        return self.lookup.get(id);
    }

    pub fn last(self: *const List) ?*Node {
        return self.list.last;
    }

    pub fn remove(self: *List, id: usize, node: *Node) void {
        self.list.remove(node);
        self.len -= 1;
        _ = self.lookup.remove(id);
    }

    pub fn prepend(self: *List, id: usize, node: *Node) !void {
        self.list.prepend(node);
        self.len += 1;
        try self.lookup.put(id, node);
    }
};

const Frame = struct {
    frameId: usize,
    pageId: usize,
    evictable: bool = false,
    node: Node,

    pub fn create(gpa: std.mem.Allocator, frameId: usize, pageId: usize) !*Frame {
        const new = try gpa.create(Frame);
        new.* = .{ .frameId = frameId, .pageId = pageId, .node = .{} };
        return new;
    }

    pub fn destroy(self: *Frame, gpa: std.mem.Allocator) void {
        gpa.destroy(self);
    }

    pub fn reset(self: *Frame, frameId: usize) void {
        self.frameId = frameId;
        self.evictable = false;
        // pageId stays the same.
    }
};

const Error = error{FrameNotFound};
