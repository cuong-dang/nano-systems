const LeafPage = @import("btree_page.zig").LeafPage;
const InternalPage = @import("btree_page.zig").InternalPage;
const Rid = @import("rid.zig").Rid;
const gpa = @import("std").testing.allocator;
const expectEqual = @import("std").testing.expectEqual;

fn intCmp(lhs: i64, rhs: i64) i32 {
    if (lhs < rhs) return -1;
    if (lhs > rhs) return 1;
    return 0;
}

const Leaf = LeafPage(i64, intCmp, 10, null);
const Internal = InternalPage(i64, intCmp, 10);

test "LeafPage.insert" {
    var leaf: Leaf = .init(0);
    leaf.insert(1, rid(0));
    leaf.insert(4, rid(1));
    leaf.insert(4, rid(2));
    try expectKvAt(&leaf, 0, 1, rid(0));
    try expectKvAt(&leaf, 1, 4, rid(1));
    try expectKvAt(&leaf, 2, 4, rid(2));

    leaf.insert(2, rid(3));
    try expectKvAt(&leaf, 1, 2, rid(3));
    leaf.insert(2, rid(4));
    try expectKvAt(&leaf, 0, 1, rid(0));
    try expectKvAt(&leaf, 1, 2, rid(3));
    try expectKvAt(&leaf, 2, 2, rid(4));
    try expectKvAt(&leaf, 3, 4, rid(1));
    try expectKvAt(&leaf, 4, 4, rid(2));

    leaf.insert(0, rid(5));
    leaf.insert(3, rid(6));
    leaf.insert(5, rid(7));
    try expectKvAt(&leaf, 0, 0, rid(5));
    try expectKvAt(&leaf, 1, 1, rid(0));
    try expectKvAt(&leaf, 2, 2, rid(3));
    try expectKvAt(&leaf, 3, 2, rid(4));
    try expectKvAt(&leaf, 4, 3, rid(6));
    try expectKvAt(&leaf, 5, 4, rid(1));
    try expectKvAt(&leaf, 6, 4, rid(2));
    try expectKvAt(&leaf, 7, 5, rid(7));
}

test "indexOf" {
    var leaf: Leaf = .init(0);
    leaf.insert(0, rid(0));
    leaf.insert(1, rid(1));
    leaf.insert(2, rid(2));
    try expectEqual(0, leaf.base.indexOf(&leaf.keys, 0));
    try expectEqual(1, leaf.base.indexOf(&leaf.keys, 1));
    try expectEqual(2, leaf.base.indexOf(&leaf.keys, 2));

    var internal: Internal = .init(1);
    internal.keys[1] = 4;
    internal.vals[0] = 0;
    internal.vals[1] = 1;
    internal.base.size = 2;
    try expectEqual(0, internal.base.indexOf(&internal.keys, 2));
}

fn expectKvAt(leaf: *Leaf, i: usize, key: i64, val: Rid) !void {
    try expectEqual(key, leaf.keys[i]);
    try expectEqual(val, leaf.vals[i]);
}

fn rid(i: u32) Rid {
    return .{ .pageId = i, .slotNum = i };
}
