const testing = @import("std").testing;

const Channel = @import("./channel.zig").Channel;

test Channel {
    var c = Channel(i32).init(testing.allocator, testing.io);
    try c.put(1);
    try testing.expectEqual(1, c.get());
}
