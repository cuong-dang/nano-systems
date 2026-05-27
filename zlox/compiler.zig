const std = @import("std");
const builtin = @import("builtin");

const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;
const Value = @import("./chunk.zig").Value;
const Scanner = @import("./scanner.zig").Scanner;
const Token = @import("./scanner.zig").Token;
const TokenType = @import("./scanner.zig").TokenType;
const debug = @import("./debug.zig");

pub const Compiler = struct {
    scanner: Scanner,
    parser: Parser,
    chunk: *Chunk,

    pub fn compile(source: []const u8, chunk: *Chunk) bool {
        var self = Compiler{ .scanner = undefined, .parser = .init(), .chunk = undefined };
        self.scanner = .init(source);
        self.parser.hadError = false;
        self.parser.panicMode = false;
        self.chunk = chunk;
        self.advance();
        self.expression();
        self.consume(.EOF, "Expect end of expression.");
        self.end();
        return !self.parser.hadError;
    }

    fn advance(self: *Compiler) void {
        self.parser.previous = self.parser.current;
        while (true) {
            self.parser.current = self.scanner.scanToken();
            if (self.parser.current.type != .ERROR) break;
            self.errorAtCurrent(self.parser.current.lexeme);
        }
    }

    fn consume(self: *Compiler, tokenType: TokenType, message: []const u8) void {
        if (self.parser.current.type == tokenType) {
            self.advance();
            return;
        }
        self.errorAtCurrent(message);
    }

    fn end(self: *Compiler) void {
        self.emitReturn();
        if (builtin.mode == .Debug and !self.parser.hadError) {
            debug.disassembleChunk(self.chunk, "code");
        }
    }

    fn binary(self: *Compiler) void {
        const operatorType = self.parser.previous.type;
        const rule = getRule(operatorType);
        self.parsePrecedence(@enumFromInt(@intFromEnum(rule.precedence) + 1));

        switch (operatorType) {
            .PLUS => self.emitByte(@intFromEnum(OpCode.ADD)),
            .MINUS => self.emitByte(@intFromEnum(OpCode.SUBTRACT)),
            .STAR => self.emitByte(@intFromEnum(OpCode.MULTIPLY)),
            .SLASH => self.emitByte(@intFromEnum(OpCode.DIVIDE)),
            else => unreachable,
        }
    }

    fn literal(self: *Compiler) void {
        switch (self.parser.previous.type) {
            .FALSE => self.emitByte(@intFromEnum(OpCode.FALSE)),
            .TRUE => self.emitByte(@intFromEnum(OpCode.TRUE)),
            .NIL => self.emitByte(@intFromEnum(OpCode.NIL)),
            else => unreachable,
        }
    }

    fn expression(self: *Compiler) void {
        self.parsePrecedence(.ASSIGNMENT);
    }

    fn grouping(self: *Compiler) void {
        self.expression();
        self.consume(.RIGHT_PAREN, "Expect ')' after expression.");
    }

    fn number(self: *Compiler) void {
        const value = std.fmt.parseFloat(f64, self.parser.previous.lexeme) catch {
            self.parser.hadError = true;
            return;
        };
        self.emitConstant(Value{ .number = value }) catch {
            self.parser.hadError = true;
            return;
        };
    }

    fn unary(self: *Compiler) void {
        const operatorType = self.parser.previous.type;

        // Compile the operand.
        self.parsePrecedence(.UNARY);

        // Emit the operator instruction.
        switch (operatorType) {
            .BANG => self.emitByte(@intFromEnum(OpCode.NOT)),
            .MINUS => self.emitByte(@intFromEnum(OpCode.NEGATE)),
            else => unreachable,
        }
    }

    fn parsePrecedence(self: *Compiler, precedence: Precedence) void {
        self.advance();
        if (getRule(self.parser.previous.type).prefix) |prefixRule| {
            prefixRule(self);
        } else {
            self.error_("Expected expression.");
        }

        while (@intFromEnum(precedence) <= @intFromEnum(getRule(self.parser.current.type).precedence)) {
            self.advance();
            if (getRule(self.parser.previous.type).infix) |infixRule| {
                infixRule(self);
            } else {
                unreachable;
            }
        }
    }

    fn emitByte(self: *Compiler, byte: u8) void {
        self.chunk.write(byte, self.parser.previous.line) catch {
            self.parser.hadError = true;
        };
    }

    fn emitBytes(self: *Compiler, byte1: u8, byte2: u8) void {
        self.emitByte(byte1);
        self.emitByte(byte2);
    }

    fn emitReturn(self: *Compiler) void {
        self.emitByte(@intFromEnum(OpCode.RETURN));
    }

    fn emitConstant(self: *Compiler, value: Value) !void {
        self.emitBytes(@intFromEnum(OpCode.CONSTANT), try self.makeConstant(value));
    }

    fn makeConstant(self: *Compiler, value: Value) !u8 {
        const constant = try self.chunk.addConstant(value);
        if (constant > std.math.maxInt(u8)) {
            self.error_("Too many constants in one chunk.");
            return 0;
        }
        return @intCast(constant);
    }

    fn errorAtCurrent(self: *Compiler, message: []const u8) void {
        self.errorAt(&self.parser.current, message);
    }

    fn error_(self: *Compiler, message: []const u8) void {
        self.errorAt(&self.parser.previous, message);
    }

    fn errorAt(self: *Compiler, token: *Token, message: []const u8) void {
        self.parser.panicMode = true;
        std.debug.print("[line {d}] Error", .{token.line});

        if (token.type == .EOF) {
            std.debug.print(" at end", .{});
        } else if (token.type == .ERROR) {
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
    panicMode: bool,

    pub fn init() Parser {
        return .{ .current = undefined, .previous = undefined, .hadError = false, .panicMode = false };
    }
};

const Precedence = enum {
    NONE,
    ASSIGNMENT, // =
    OR, // or
    AND, // and
    EQUALITY, // == !=
    COMPARISON, // < > <= >=
    TERM, // + -
    FACTOR, // * /
    UNARY, // ! -
    CALL, // . ()
    PRIMARY,
};

const ParseFn = *const fn (*Compiler) void;

const ParseRule = struct { prefix: ?ParseFn, infix: ?ParseFn, precedence: Precedence };

const rules = blk: {
    var r: [@intFromEnum(TokenType.EOF) + 1]ParseRule = undefined;

    r[@intFromEnum(TokenType.LEFT_PAREN)] = .{ .prefix = Compiler.grouping, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.RIGHT_PAREN)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.LEFT_BRACE)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.RIGHT_BRACE)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.COMMA)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.DOT)] = .{ .prefix = null, .infix = null, .precedence = .NONE };

    r[@intFromEnum(TokenType.MINUS)] = .{ .prefix = Compiler.unary, .infix = Compiler.binary, .precedence = .TERM };
    r[@intFromEnum(TokenType.PLUS)] = .{ .prefix = null, .infix = Compiler.binary, .precedence = .TERM };

    r[@intFromEnum(TokenType.SEMICOLON)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.SLASH)] = .{ .prefix = null, .infix = Compiler.binary, .precedence = .FACTOR };
    r[@intFromEnum(TokenType.STAR)] = .{ .prefix = null, .infix = Compiler.binary, .precedence = .FACTOR };

    r[@intFromEnum(TokenType.BANG)] = .{ .prefix = Compiler.unary, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.BANG_EQUAL)] = .{ .prefix = null, .infix = null, .precedence = .NONE };

    r[@intFromEnum(TokenType.EQUAL)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.EQUAL_EQUAL)] = .{ .prefix = null, .infix = null, .precedence = .NONE };

    r[@intFromEnum(TokenType.GREATER)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.GREATER_EQUAL)] = .{ .prefix = null, .infix = null, .precedence = .NONE };

    r[@intFromEnum(TokenType.LESS)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.LESS_EQUAL)] = .{ .prefix = null, .infix = null, .precedence = .NONE };

    r[@intFromEnum(TokenType.IDENTIFIER)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.STRING)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.NUMBER)] = .{ .prefix = Compiler.number, .infix = null, .precedence = .NONE };

    r[@intFromEnum(TokenType.AND)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.CLASS)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.ELSE)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.FALSE)] = .{ .prefix = Compiler.literal, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.FOR)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.FUN)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.IF)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.NIL)] = .{ .prefix = Compiler.literal, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.OR)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.PRINT)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.RETURN)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.SUPER)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.THIS)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.TRUE)] = .{ .prefix = Compiler.literal, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.VAR)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.WHILE)] = .{ .prefix = null, .infix = null, .precedence = .NONE };

    r[@intFromEnum(TokenType.ERROR)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.EOF)] = .{ .prefix = null, .infix = null, .precedence = .NONE };

    break :blk r;
};

fn getRule(tokenType: TokenType) *const ParseRule {
    return &rules[@intFromEnum(tokenType)];
}
