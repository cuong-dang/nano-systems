const std = @import("std");

const DiskManager = @import("./storage/disk/disk_manager.zig").DiskManager;

pub fn main(init: std.process.Init) !void {
    var db = try DiskManager.init(init.gpa, init.io, "/Users/cuong/code/nano-systems/db/main.db");
    defer db.deinit();
    try db.writePage(0, "Hello, db!");
}
