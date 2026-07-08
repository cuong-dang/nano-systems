const testing = @import("std").testing;

const ArcReplacer = @import("./arc_replacer.zig").ArcReplacer;

test "bustub::SampleTest" {
    var arc: ArcReplacer = .init(testing.allocator, testing.io, 7);
    defer arc.deinit();

    try arc.recordAccess(1, 1);
    try arc.recordAccess(2, 2);
    try arc.recordAccess(3, 3);
    try arc.recordAccess(4, 4);
    try arc.recordAccess(5, 5);
    try arc.recordAccess(6, 6);
    try arc.setEvictable(1, true);
    try arc.setEvictable(2, true);
    try arc.setEvictable(3, true);
    try arc.setEvictable(4, true);
    try arc.setEvictable(5, true);
    try arc.setEvictable(6, false);
    try testing.expectEqual(5, arc.numEvictable);

    try arc.recordAccess(1, 1);
    try testing.expectEqual(5, arc.mru.len);
    try testing.expectEqual(1, arc.mfu.len);
    try testing.expectEqual(2, try arc.evict());
    try testing.expectEqual(3, try arc.evict());
    try testing.expectEqual(4, try arc.evict());
    try testing.expectEqual(2, arc.numEvictable);
    try testing.expectEqual(3, arc.mruGhost.len);

    try arc.recordAccess(2, 7);
    try arc.setEvictable(2, true);
    try arc.recordAccess(3, 2);
    try arc.setEvictable(3, true);
    try testing.expectEqual(1, arc.mruTargetSize);
    try testing.expectEqual(2, arc.mruGhost.len);
    try testing.expectEqual(4, arc.numEvictable);
    try testing.expectEqual(1, arc.mruTargetSize);

    try arc.recordAccess(4, 3);
    try arc.setEvictable(4, true);
    try arc.recordAccess(7, 4);
    try arc.setEvictable(7, true);
    try testing.expectEqual(6, arc.numEvictable);
    try testing.expectEqual(3, arc.mruTargetSize);

    try testing.expectEqual(5, try arc.evict());
    try testing.expectEqual(1, try arc.evict());
    try testing.expectEqual(1, arc.mruGhost.len);
    try testing.expectEqual(1, arc.mfuGhost.len);

    try arc.recordAccess(5, 1);
    try arc.setEvictable(5, true);
    try testing.expectEqual(2, arc.mruTargetSize);
    try testing.expectEqual(2, arc.evict());
}

test "bustub::SampleTest2" {
    var arc: ArcReplacer = .init(testing.allocator, testing.io, 3);
    defer arc.deinit();

    try arc.recordAccess(1, 1);
    try arc.setEvictable(1, true);
    try arc.recordAccess(2, 2);
    try arc.setEvictable(2, true);
    try arc.recordAccess(3, 3);
    try arc.setEvictable(3, true);
    try testing.expectEqual(3, arc.numEvictable);

    try testing.expectEqual(1, try arc.evict());
    try testing.expectEqual(2, try arc.evict());
    try testing.expectEqual(3, try arc.evict());
    try testing.expectEqual(0, arc.numEvictable);

    try arc.recordAccess(3, 4);
    try arc.setEvictable(3, true);
    try arc.recordAccess(2, 1);
    try arc.setEvictable(2, true);
    try testing.expectEqual(2, arc.numEvictable);
    try arc.recordAccess(1, 3);
    try arc.setEvictable(1, true);
    try testing.expectEqual(3, try arc.evict());
    try testing.expectEqual(2, try arc.evict());
    try testing.expectEqual(1, try arc.evict());

    try arc.recordAccess(1, 1);
    try arc.setEvictable(1, true);
    try arc.recordAccess(2, 4);
    try arc.setEvictable(2, true);
    try arc.recordAccess(3, 5);
    try arc.setEvictable(3, true);
    try testing.expectEqual(1, try arc.evict());
    try arc.recordAccess(1, 6);
    try arc.setEvictable(1, true);
    try testing.expectEqual(2, try arc.evict());
    try arc.recordAccess(2, 7);
    try arc.setEvictable(2, true);
    try testing.expectEqual(3, try arc.evict());
    try arc.recordAccess(3, 5);
    try arc.setEvictable(3, true);
    try testing.expectEqual(3, try arc.evict());
    try arc.recordAccess(3, 2);
    try arc.setEvictable(3, true);
    try testing.expectEqual(1, try arc.evict());
    try arc.recordAccess(1, 3);
    try arc.setEvictable(1, true);
    try testing.expectEqual(2, try arc.evict());
    try testing.expectEqual(3, try arc.evict());
    try testing.expectEqual(1, try arc.evict());
}

test "remove should not leak memory" {
    var arc: ArcReplacer = .init(testing.allocator, testing.io, 7);
    defer arc.deinit();

    try arc.recordAccess(1, 1);
    try arc.setEvictable(1, true);
    arc.remove(1);
}
