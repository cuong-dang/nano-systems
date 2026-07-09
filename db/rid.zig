const PageId = @import("page.zig").PageId;
const SlotNum = @import("page.zig").SlotNum;

pub const Rid = struct {
    pageId: PageId,
    slotNum: SlotNum,
};
