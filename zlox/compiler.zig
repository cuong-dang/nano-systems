const std = @import("std");

const Chunk = @import("./chunk.zig").Chunk;
const Scanner = @import("./scanner.zig").Scanner;
const Token = @import("./scanner.zig").Token;

pub const Compiler = struct {
    scanner: Scanner,
    parser: Parser,

    pub fn init(source: []const u8) Compiler {
        return .{ .scanner = .init(source), .parser = .{} };
    }

    pub fn compile(self: *Compiler, chunk: *Chunk) void {
        self.advance();
        self.expression();
        self.consume(.EOF, "Expect end of expression.");
    }

    fn advance(self: *Compiler) void {
        self.parser.previous = self.parser.current;
        while (true) {
            self.parser.current = self.scanner.scanToken();
            if (self.parser.current.type != .ERROR) break;
            self.errorAtCurrent(self.parser.current.lexeme);
        }
    }

    fn errorAtCurrent(self: *const Compiler, message: []const u8) void {
        self.errorAt(&self.parser.current, message);
    }

    fn error_(self: *const Compiler, message: []const u8) void {
        self.errorAt(&self.parser.previous, message);
    }

    fn errorAt(self: *const Compiler, token: Token, message: []const u8) void {
        std.debug.print("[line {d}] Error", .{token.line});

        if (token.tokenType == .EOF) {
            std.debug.print(" at end", .{});
        } else if (token.TokenType == .ERROR) {
            // Nothing.
        } else {
            std.debug.print(" at '{s}'", .{token.lexeme});
        }

        std.debug.print(": {s}\n", .{message});
        self.parser.hadError = true;
    }
};

const Parser = struct {
    current: Token,
    previous: Token,
    hadError: bool,
};
