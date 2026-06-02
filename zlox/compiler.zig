const std = @import("std");
const builtin = @import("builtin");

const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;
const Value = @import("./value.zig").Value;
const Obj = @import("./value.zig").Obj;
const Scanner = @import("./scanner.zig").Scanner;
const Token = @import("./scanner.zig").Token;
const TokenType = @import("./scanner.zig").TokenType;
const VM = @import("./vm.zig").VM;
const debug = @import("./debug.zig");

pub const Compiler = struct {
    gpa: std.mem.Allocator,
    scanner: Scanner,
    parser: Parser,
    vm: *VM,

    pub fn compile(gpa: std.mem.Allocator, source: []const u8, vm: *VM) bool {
        var self = Compiler{ .gpa = gpa, .scanner = undefined, .parser = .init(), .vm = vm };
        self.scanner = .init(source);
        self.parser.hadError = false;
        self.parser.panicMode = false;
        self.advance();

        while (!self.match(.EOF)) {
            self.declaration();
        }

        self.end();
        return !self.parser.hadError;
    }

    // Movements.
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

    fn match(self: *Compiler, tokenType: TokenType) bool {
        if (!self.check(tokenType)) return false;
        self.advance();
        return true;
    }

    fn check(self: *Compiler, tokenType: TokenType) bool {
        return self.parser.current.type == tokenType;
    }

    fn end(self: *Compiler) void {
        self.emitReturn();
    }

    // Parsing functions.
    fn declaration(self: *Compiler) void {
        if (self.match(.VAR)) {
            self.varDeclaration();
        } else {
            self.statement();
        }

        if (self.parser.panicMode) self.synchronize();
    }

    fn varDeclaration(self: *Compiler) void {
        const global = self.parseVariable("Expect variable name.") catch {
            self.parser.hadError = true;
            return;
        };

        if (self.match(.EQUAL)) {
            self.expression();
        } else {
            self.emitOp(.NIL);
        }
        self.consume(.SEMICOLON, "Expect ';' after variable declaration.");

        self.defineVariable(global);
    }

    fn statement(self: *Compiler) void {
        if (self.match(.PRINT)) {
            self.printStatement();
        } else {
            self.expressionStatement();
        }
    }

    fn printStatement(self: *Compiler) void {
        self.expression();
        self.consume(.SEMICOLON, "Expect ';' after value.");
        self.emitOp(.PRINT);
    }

    fn expressionStatement(self: *Compiler) void {
        self.expression();
        self.consume(.SEMICOLON, "Expect ';' after expression.");
        self.emitOp(.POP);
    }

    fn expression(self: *Compiler) void {
        self.parsePrecedence(.ASSIGNMENT);
    }

    fn parsePrecedence(self: *Compiler, precedence: Precedence) void {
        const canAssign = @intFromEnum(precedence) <= @intFromEnum(Precedence.ASSIGNMENT);

        self.advance();
        if (getRule(self.parser.previous.type).prefix) |prefixRule| {
            prefixRule(self, canAssign);
        } else {
            self.error_("Expected expression.");
        }

        while (@intFromEnum(precedence) <= @intFromEnum(getRule(self.parser.current.type).precedence)) {
            self.advance();
            if (getRule(self.parser.previous.type).infix) |infixRule| {
                infixRule(self, canAssign);
            } else {
                unreachable;
            }
        }

        if (canAssign and self.match(.EQUAL)) {
            self.error_("Invalid assignment target.");
        }
    }

    fn unary(self: *Compiler, canAssign: bool) void {
        _ = canAssign;
        const operatorType = self.parser.previous.type;

        // Compile the operand.
        self.parsePrecedence(.UNARY);

        // Emit the operator instruction.
        switch (operatorType) {
            .BANG => self.emitOp(.NOT),
            .MINUS => self.emitOp(.NEGATE),
            else => unreachable,
        }
    }

    fn binary(self: *Compiler, canAssign: bool) void {
        _ = canAssign;
        const operatorType = self.parser.previous.type;
        const rule = getRule(operatorType);
        self.parsePrecedence(@enumFromInt(@intFromEnum(rule.precedence) + 1));

        switch (operatorType) {
            .PLUS => self.emitOp(.ADD),
            .MINUS => self.emitOp(.SUBTRACT),
            .STAR => self.emitOp(.MULTIPLY),
            .SLASH => self.emitOp(.DIVIDE),
            .BANG_EQUAL => self.emitBytes(@intFromEnum(OpCode.EQUAL), @intFromEnum(OpCode.NOT)),
            .EQUAL_EQUAL => self.emitOp(.EQUAL),
            .GREATER => self.emitOp(.GREATER),
            .GREATER_EQUAL => self.emitBytes(@intFromEnum(OpCode.LESS), @intFromEnum(OpCode.NOT)),
            .LESS => self.emitOp(.LESS),
            .LESS_EQUAL => self.emitBytes(@intFromEnum(OpCode.GREATER), @intFromEnum(OpCode.NOT)),
            else => unreachable,
        }
    }

    fn literal(self: *Compiler, canAssign: bool) void {
        _ = canAssign;
        switch (self.parser.previous.type) {
            .FALSE => self.emitOp(.FALSE),
            .TRUE => self.emitOp(.TRUE),
            .NIL => self.emitOp(.NIL),
            else => unreachable,
        }
    }

    fn grouping(self: *Compiler, canAssign: bool) void {
        _ = canAssign;
        self.expression();
        self.consume(.RIGHT_PAREN, "Expect ')' after expression.");
    }

    fn number(self: *Compiler, canAssign: bool) void {
        _ = canAssign;
        const v = std.fmt.parseFloat(f64, self.parser.previous.lexeme) catch {
            self.parser.hadError = true;
            return;
        };
        self.emitConstant(.{ .number = v }) catch {
            self.parser.hadError = true;
            return;
        };
    }

    fn string(self: *Compiler, canAssign: bool) void {
        _ = canAssign;
        const obj = Obj.fromString(self.gpa, self.parser.previous.lexeme) catch {
            self.parser.hadError = true;
            return;
        };
        self.vm.addObject(obj);
        self.emitConstant(.{ .obj = obj }) catch {
            self.parser.hadError = true;
            return;
        };
    }

    fn variable(self: *Compiler, canAssign: bool) void {
        self.namedVariable(self.parser.previous.lexeme, canAssign);
    }

    fn namedVariable(self: *Compiler, name: []const u8, canAssign: bool) void {
        const arg = self.identifierConstant(name) catch {
            self.parser.hadError = true;
            return;
        };
        if (canAssign and self.match(.EQUAL)) {
            self.expression();
            self.emitBytes(@intFromEnum(OpCode.SET_GLOBAL), arg);
        } else {
            self.emitBytes(@intFromEnum(OpCode.GET_GLOBAL), arg);
        }
    }

    fn parseVariable(self: *Compiler, errorMessage: []const u8) !u8 {
        self.consume(.IDENTIFIER, errorMessage);
        return try self.identifierConstant(self.parser.previous.lexeme);
    }

    fn identifierConstant(self: *Compiler, name: []const u8) !u8 {
        return try self.makeConstant(try Value.fromIdentifier(self.gpa, name));
    }

    fn defineVariable(self: *Compiler, global: u8) void {
        self.emitBytes(@intFromEnum(OpCode.DEFINE_GLOBAL), global);
    }

    // Emits.
    fn emitOp(self: *Compiler, op: OpCode) void {
        self.emitByte(@intFromEnum(op));
    }

    fn emitByte(self: *Compiler, byte: u8) void {
        self.vm.chunk.write(byte, self.parser.previous.line) catch {
            self.parser.hadError = true;
        };
    }

    fn emitBytes(self: *Compiler, byte1: u8, byte2: u8) void {
        self.emitByte(byte1);
        self.emitByte(byte2);
    }

    fn emitReturn(self: *Compiler) void {
        self.emitOp(.RETURN);
    }

    fn emitConstant(self: *Compiler, v: Value) !void {
        self.emitBytes(@intFromEnum(OpCode.CONSTANT), try self.makeConstant(v));
    }

    fn makeConstant(self: *Compiler, v: Value) !u8 {
        const constant = try self.vm.chunk.addConstant(v);
        if (constant > std.math.maxInt(u8)) {
            self.error_("Too many constants in one chunk.");
            return 0;
        }
        return @intCast(constant);
    }

    // Errors.
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

    fn errorAtCurrent(self: *Compiler, message: []const u8) void {
        self.errorAt(&self.parser.current, message);
    }

    fn synchronize(self: *Compiler) void {
        self.parser.panicMode = false;

        while (self.parser.current.type != .EOF) {
            if (self.parser.previous.type == .SEMICOLON) return;
            switch (self.parser.current.type) {
                .RETURN => return,
                else => self.advance(),
            }
        }
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

const ParseFn = *const fn (*Compiler, bool) void;

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
    r[@intFromEnum(TokenType.BANG_EQUAL)] = .{ .prefix = null, .infix = Compiler.binary, .precedence = .EQUALITY };

    r[@intFromEnum(TokenType.EQUAL)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.EQUAL_EQUAL)] = .{ .prefix = null, .infix = Compiler.binary, .precedence = .EQUALITY };

    r[@intFromEnum(TokenType.GREATER)] = .{ .prefix = null, .infix = Compiler.binary, .precedence = .COMPARISON };
    r[@intFromEnum(TokenType.GREATER_EQUAL)] = .{ .prefix = null, .infix = Compiler.binary, .precedence = .COMPARISON };

    r[@intFromEnum(TokenType.LESS)] = .{ .prefix = null, .infix = Compiler.binary, .precedence = .COMPARISON };
    r[@intFromEnum(TokenType.LESS_EQUAL)] = .{ .prefix = null, .infix = Compiler.binary, .precedence = .COMPARISON };

    r[@intFromEnum(TokenType.IDENTIFIER)] = .{ .prefix = Compiler.variable, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.STRING)] = .{ .prefix = Compiler.string, .infix = null, .precedence = .NONE };
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
