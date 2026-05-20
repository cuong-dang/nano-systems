const print = @import("std").debug.print;

const Scanner = @import("./scanner.zig").Scanner;

pub const Compiler = struct {
    pub fn compile(source: []const u8) void {
        var scanner = Scanner.init(source);
        var line: usize = 0;

        while (true) {
            const token = scanner.scanToken();

            if (token.tokenType == .EOF) break;
            if (token.line != line) {
                print("{d:>4} ", .{token.line});
                line = token.line;
            } else {
                print("   | ", .{});
            }
            print("{d:>2} '{s}'\n", .{ token.tokenType, token.lexeme });
        }
    }
};
