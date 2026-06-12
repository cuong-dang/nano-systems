const testing = @import("std").testing;

const ArcReplacer = @import("./arc_replacer.zig").ArcReplacer;

test "SampleTest" { // from bustub
    var arc: ArcReplacer = .init(testing.allocator, 7);
    defer arc.deinit();
    try arc.recordAccess(1, 1);
}
