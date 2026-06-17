const std = @import("std");
const Node = std.DoublyLinkedList.Node;

pub fn Channel(comptime T: type) type {
    const Element = struct {
        data: T,
        node: Node,
    };

    return struct {
        gpa: std.mem.Allocator,
        io: std.Io,
        mu: std.Io.Mutex = .init,
        cond: std.Io.Condition = .init,

        q: std.DoublyLinkedList = .{},

        pub fn init(gpa: std.mem.Allocator, io: std.Io) Channel(T) {
            return .{ .gpa = gpa, .io = io };
        }

        pub fn put(self: *Channel(T), data: T) !void {
            var new = try self.gpa.create(Element);
            new.* = .{ .data = data, .node = .{} };

            self.mu.lockUncancelable(self.io);
            self.q.append(&new.node);
            self.mu.unlock(self.io);

            self.cond.signal(self.io);
        }

        pub fn get(self: *Channel(T)) T {
            self.mu.lockUncancelable(self.io);

            while (self.q.first == null) {
                self.cond.waitUncancelable(self.io, &self.mu);
            }

            const node = self.q.popFirst().?;
            self.mu.unlock(self.io);

            const element: *Element = @fieldParentPtr("node", node);
            const data = element.data;
            self.gpa.destroy(element);
            return data;
        }
    };
}
