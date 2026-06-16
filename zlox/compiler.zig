const std = @import("std");
const builtin = @import("builtin");

const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;
const Value = @import("./value.zig").Value;
const Obj = @import("./value.zig").Obj;
const Function = @import("./value.zig").Function;
const Scanner = @import("./scanner.zig").Scanner;
const Token = @import("./scanner.zig").Token;
const TokenType = @import("./scanner.zig").TokenType;
const VM = @import("./vm.zig").VM;
const debug = @import("./debug.zig");

pub const Compiler = struct {
    gpa: std.mem.Allocator,

    locals: [std.math.maxInt(u8) + 1]Local = undefined,
    localCount: u8 = 0,
    scopeDepth: usize = 0,

    scanner: *Scanner = undefined,
    parser: *Parser = undefined,
    stringConstants: std.StringHashMap(u8),
    vm: *VM,

    functionObj: *Obj,
    function: *Function = undefined,
    functionType: FunctionType,

    pub fn init(gpa: std.mem.Allocator, vm: *VM, funType: FunctionType, scanner: ?*Scanner, parser: ?*Parser) !*Compiler {
        const compiler = try gpa.create(Compiler);
        compiler.* = Compiler{ .gpa = gpa, .stringConstants = .init(gpa), .vm = vm, .functionObj = try Obj.newFunction(gpa), .functionType = funType };
        compiler.function = &compiler.functionObj.data.function;

        if (scanner) |s| {
            compiler.scanner = s;
        } else {
            compiler.scanner = try gpa.create(Scanner);
        }
        if (parser) |p| {
            compiler.parser = p;
        } else {
            compiler.parser = try gpa.create(Parser);
            compiler.parser.* = .init();
        }

        const local = &compiler.locals[compiler.localCount];
        local.depth = 0;
        local.name = "";
        compiler.localCount += 1;
        return compiler;
    }

    pub fn deinit(self: *Compiler, ownedScannerParser: bool) void {
        if (ownedScannerParser) {
            self.gpa.destroy(self.scanner);
            self.gpa.destroy(self.parser);
        }
        self.stringConstants.deinit();
        self.gpa.destroy(self);
    }

    pub fn compile(self: *Compiler, source: []const u8) ?*Obj {
        self.scanner.* = .init(source);
        self.parser.hadError = false;
        self.parser.panicMode = false;
        self.advance();

        while (!self.match(.EOF)) {
            self.declaration();
        }

        return if (self.parser.hadError) null else self.end();
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

    fn end(self: *Compiler) *Obj {
        self.emitReturn();
        if (builtin.mode == .Debug) {
            const name = if (self.function.name.len != 0) std.fmt.allocPrint(self.gpa, "<fn {s}>", .{self.function.name}) catch unreachable else "<script>";
            debug.disassembleChunk(&self.function.chunk, name);
        }
        return self.functionObj;
    }

    // Parsing functions.
    fn declaration(self: *Compiler) void {
        if (self.match(.FUN)) {
            self.funDeclaration();
        } else if (self.match(.VAR)) {
            self.varDeclaration();
        } else {
            self.statement();
        }

        if (self.parser.panicMode) self.synchronize();
    }

    fn funDeclaration(self: *Compiler) void {
        const global = self.parseVariable("Expect function name.") catch {
            self.parser.hadError = true;
            return;
        };
        self.markInitialized();
        self.fun(.FUNCTION);
        self.defineVariable(global);
    }

    fn fun(self: *Compiler, funType: FunctionType) void {
        var funCompiler = Compiler.init(self.gpa, self.vm, funType, self.scanner, self.parser) catch {
            self.parser.hadError = true;
            return;
        };
        defer funCompiler.deinit(false);
        funCompiler.function.name = funCompiler.gpa.alloc(u8, self.parser.previous.lexeme.len) catch {
            self.parser.hadError = true;
            return;
        };
        @memcpy(funCompiler.function.name, self.parser.previous.lexeme);
        funCompiler.beginScope();
        funCompiler.consume(.LEFT_PAREN, "Expect '(' after function name.");
        if (!funCompiler.check(.RIGHT_PAREN)) {
            while (true) {
                funCompiler.function.arity += 1;
                if (funCompiler.function.arity > 255) {
                    funCompiler.errorAtCurrent("Can't have more than 255 parameters.");
                }
                const constant = funCompiler.parseVariable("Expect parameter name.") catch {
                    funCompiler.parser.hadError = true;
                    return;
                };
                funCompiler.defineVariable(constant);
                if (!funCompiler.match(.COMMA)) break;
            }
        }
        funCompiler.consume(.RIGHT_PAREN, "Expect ')' after parameters.");
        funCompiler.consume(.LEFT_BRACE, "Expect '{' before function body.");
        funCompiler.block();
        const function = funCompiler.end();
        self.vm.addObject(function);
        self.emitBytes(@intFromEnum(OpCode.CONSTANT), self.makeConstant(.{ .obj = function }) catch {
            self.parser.hadError = true;
            return;
        });
    }

    fn call(self: *Compiler, canAssign: bool) void {
        _ = canAssign;
        const argCount = self.argumentList();
        self.emitBytes(@intFromEnum(OpCode.CALL), argCount);
    }

    fn argumentList(self: *Compiler) u8 {
        var argCount: u8 = 0;
        if (!self.check(.RIGHT_PAREN)) {
            while (true) {
                self.expression();
                if (argCount == 255) {
                    self.error_("Can't have more than 255 arguments.");
                }
                argCount += 1;
                if (!self.match(.COMMA)) break;
            }
        }
        self.consume(.RIGHT_PAREN, "Expect ')' after arguments.");
        return argCount;
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
        } else if (self.match(.IF)) {
            self.ifStatement();
        } else if (self.match(.WHILE)) {
            self.whileStatement();
        } else if (self.match(.FOR)) {
            self.forStatement();
        } else if (self.match(.RETURN)) {
            self.returnStatement();
        } else if (self.match(.LEFT_BRACE)) {
            self.beginScope();
            self.block();
            self.endScope();
        } else {
            self.expressionStatement();
        }
    }

    fn printStatement(self: *Compiler) void {
        self.expression();
        self.consume(.SEMICOLON, "Expect ';' after value.");
        self.emitOp(.PRINT);
    }

    fn ifStatement(self: *Compiler) void {
        self.consume(.LEFT_PAREN, "Expect '(' after 'if'.");
        self.expression();
        self.consume(.RIGHT_PAREN, "Expect ')' after condition.");

        const thenJump = self.emitJump(.JUMP_IF_FALSE);
        self.emitOp(.POP);
        self.statement();
        const elseJump = self.emitJump(.JUMP);
        self.patchJump(thenJump);
        self.emitOp(.POP);

        if (self.match(.ELSE)) {
            self.statement();
        }
        self.patchJump(elseJump);
    }

    fn whileStatement(self: *Compiler) void {
        const loopStart = self.function.chunk.count();
        self.consume(.LEFT_PAREN, "Expect '(' after 'while'.");
        self.expression();
        self.consume(.RIGHT_PAREN, "Expect ')' after condition.");
        const exitJump = self.emitJump(.JUMP_IF_FALSE);
        self.emitOp(.POP);
        self.statement();
        self.emitLoop(loopStart);
        self.patchJump(exitJump);
        self.emitOp(.POP);
    }

    fn forStatement(self: *Compiler) void {
        self.beginScope();
        self.consume(.LEFT_PAREN, "Expect '(' after 'for'.");
        // Initializer.
        if (self.match(.SEMICOLON)) {
            // No initializer.
        } else if (self.match(.VAR)) {
            self.varDeclaration();
        } else {
            self.expressionStatement();
        }
        // Condition.
        var loopStart = self.function.chunk.count();
        var exitJump: ?usize = null;
        if (!self.match(.SEMICOLON)) {
            self.expression();
            self.consume(.SEMICOLON, "Expect ';' after loop condition.");
            exitJump = self.emitJump(.JUMP_IF_FALSE);
            self.emitOp(.POP);
        }
        // Increment.
        if (!self.match(.RIGHT_PAREN)) {
            const bodyJump = self.emitJump(.JUMP);
            const incrementStart = self.function.chunk.count();
            self.expression();
            self.emitOp(.POP);
            self.consume(.RIGHT_PAREN, "Expect ')' after for clauses.");

            self.emitLoop(loopStart);
            loopStart = incrementStart;
            self.patchJump(bodyJump);
        }
        // Body.
        self.statement();
        self.emitLoop(loopStart);
        if (exitJump != null) {
            self.patchJump(exitJump.?);
            self.emitOp(.POP);
        }
        self.endScope();
    }

    fn returnStatement(self: *Compiler) void {
        if (self.functionType == .SCRIPT) {
            self.error_("Can't return from top-level code.");
        }

        if (self.match(.SEMICOLON)) {
            self.emitReturn();
        } else {
            self.expression();
            self.consume(.SEMICOLON, "Expect ';' after return value.");
            self.emitOp(.RETURN);
        }
    }

    fn block(self: *Compiler) void {
        while (!self.check(.RIGHT_BRACE) and !self.check(.EOF)) {
            self.declaration();
        }
        self.consume(.RIGHT_BRACE, "Expect '}' after block.");
    }

    fn beginScope(self: *Compiler) void {
        self.scopeDepth += 1;
    }

    fn endScope(self: *Compiler) void {
        self.scopeDepth -= 1;

        while (self.localCount > 0 and self.locals[self.localCount - 1].depth != null and self.locals[self.localCount - 1].depth.? > self.scopeDepth) : (self.localCount -= 1) {
            self.emitOp(.POP);
        }
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

    fn and_(self: *Compiler, canAssign: bool) void {
        _ = canAssign;
        const endJump = self.emitJump(.JUMP_IF_FALSE);
        self.emitOp(.POP);
        self.parsePrecedence(.AND);
        self.patchJump(endJump);
    }

    fn or_(self: *Compiler, canAssign: bool) void {
        _ = canAssign;
        const elseJump = self.emitJump(.JUMP_IF_FALSE);
        const endJump = self.emitJump(.JUMP);
        self.patchJump(elseJump);
        self.emitOp(.POP);
        self.parsePrecedence(.OR);
        self.patchJump(endJump);
    }

    // Variables.
    fn variable(self: *Compiler, canAssign: bool) void {
        self.namedVariable(self.parser.previous.lexeme, canAssign);
    }

    fn namedVariable(self: *Compiler, name: []const u8, canAssign: bool) void {
        var getOp: OpCode = undefined;
        var setOp: OpCode = undefined;
        var arg = self.resolveLocal(name);
        if (arg != null) {
            getOp = .GET_LOCAL;
            setOp = .SET_LOCAL;
        } else {
            arg = self.identifierConstant(name) catch {
                self.parser.hadError = true;
                return;
            };
            getOp = .GET_GLOBAL;
            setOp = .SET_GLOBAL;
        }

        if (canAssign and self.match(.EQUAL)) {
            self.expression();
            self.emitBytes(@intFromEnum(setOp), arg.?);
        } else {
            self.emitBytes(@intFromEnum(getOp), arg.?);
        }
    }

    fn resolveLocal(self: *Compiler, name: []const u8) ?u8 {
        if (self.localCount == 0) return null;
        var i = self.localCount - 1;
        while (i >= 0) : (i -= 1) {
            if (std.mem.eql(u8, self.locals[i].name, name)) {
                if (self.locals[i].depth == null) {
                    self.error_("Can't read local variable in its own initializer.");
                }
                return i;
            }
            if (i == 0) break;
        }
        return null;
    }

    fn parseVariable(self: *Compiler, errorMessage: []const u8) !u8 {
        self.consume(.IDENTIFIER, errorMessage);

        self.declareVariable();
        if (self.scopeDepth > 0) return 0;

        return try self.identifierConstant(self.parser.previous.lexeme);
    }

    fn declareVariable(self: *Compiler) void {
        if (self.scopeDepth == 0) return;
        if (self.localCount > 0) {
            var i = self.localCount - 1;
            while (i >= 0) : (i -= 1) {
                const local = &self.locals[i];
                if (local.depth != null and local.depth.? < self.scopeDepth) {
                    break;
                }

                if (std.mem.eql(u8, self.parser.previous.lexeme, local.name)) {
                    self.error_("Already a variable with this name in this scope.");
                }

                if (i == 0) break;
            }
        }

        self.addLocal(self.parser.previous.lexeme);
    }

    fn addLocal(self: *Compiler, name: []const u8) void {
        if (self.localCount == std.math.maxInt(u8)) {
            self.error_("Too many local variables in function.");
            return;
        }

        const local = &self.locals[self.localCount];
        local.name = name;
        local.depth = null;
        self.localCount += 1;
    }

    fn identifierConstant(self: *Compiler, name: []const u8) !u8 {
        return try self.resolveConstant(try Value.fromIdentifier(self.gpa, name));
    }

    fn defineVariable(self: *Compiler, global: u8) void {
        if (self.scopeDepth > 0) {
            self.markInitialized();
            return;
        }
        self.emitBytes(@intFromEnum(OpCode.DEFINE_GLOBAL), global);
    }

    fn markInitialized(self: *Compiler) void {
        if (self.scopeDepth == 0) return;
        self.locals[self.localCount - 1].depth = self.scopeDepth;
    }

    // Emits.
    fn emitOp(self: *Compiler, op: OpCode) void {
        self.emitByte(@intFromEnum(op));
    }

    fn emitByte(self: *Compiler, byte: u8) void {
        self.function.chunk.write(byte, self.parser.previous.line) catch {
            self.parser.hadError = true;
        };
    }

    fn emitBytes(self: *Compiler, byte1: u8, byte2: u8) void {
        self.emitByte(byte1);
        self.emitByte(byte2);
    }

    fn emitReturn(self: *Compiler) void {
        self.emitOp(.NIL);
        self.emitOp(.RETURN);
    }

    fn emitConstant(self: *Compiler, v: Value) !void {
        self.emitBytes(@intFromEnum(OpCode.CONSTANT), try self.resolveConstant(v));
    }

    fn resolveConstant(self: *Compiler, v: Value) !u8 {
        switch (v) {
            .obj => |o| switch (o.data) {
                .string => |s| {
                    if (!self.stringConstants.contains(s)) {
                        try self.stringConstants.put(s, try self.makeConstant(v));
                    }
                    return self.stringConstants.get(s).?;
                },
                else => unreachable,
            },
            else => return try self.makeConstant(v),
        }
    }

    fn makeConstant(self: *Compiler, v: Value) !u8 {
        const constant = try self.function.chunk.addConstant(v);
        if (constant > std.math.maxInt(u8)) {
            self.error_("Too many constants in one chunk.");
            return 0;
        }
        return @intCast(constant);
    }

    fn emitJump(self: *Compiler, instruction: OpCode) usize {
        self.emitOp(instruction);
        self.emitByte(0xff);
        self.emitByte(0xff);
        return self.function.chunk.count() - 2;
    }

    fn patchJump(self: *Compiler, offset: usize) void {
        // -2 to adjust for the bytecode for the jump offset itself.
        const jump = self.function.chunk.count() - offset - 2;
        if (jump > std.math.maxInt(u16)) {
            self.error_("Too much code to jump over.");
        }

        self.function.chunk._code.items[offset] = @intCast((jump >> 8) & 0xff);
        self.function.chunk._code.items[offset + 1] = @intCast(jump & 0xff);
    }

    fn emitLoop(self: *Compiler, loopStart: usize) void {
        self.emitOp(.LOOP);
        const offset = self.function.chunk.count() - loopStart + 2;
        if (offset > std.math.maxInt(u16)) self.error_("Loop body too large.");
        self.emitByte(@intCast((offset >> 8) & 0xff));
        self.emitByte(@intCast(offset & 0xff));
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

const FunctionType = enum {
    FUNCTION,
    SCRIPT,
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

const Local = struct {
    name: []const u8,
    depth: ?usize,
};

const ParseFn = *const fn (*Compiler, bool) void;

const ParseRule = struct { prefix: ?ParseFn, infix: ?ParseFn, precedence: Precedence };

const rules = blk: {
    var r: [@intFromEnum(TokenType.EOF) + 1]ParseRule = undefined;

    r[@intFromEnum(TokenType.LEFT_PAREN)] = .{ .prefix = Compiler.grouping, .infix = Compiler.call, .precedence = .CALL };
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

    r[@intFromEnum(TokenType.AND)] = .{ .prefix = null, .infix = Compiler.and_, .precedence = .AND };
    r[@intFromEnum(TokenType.CLASS)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.ELSE)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.FALSE)] = .{ .prefix = Compiler.literal, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.FOR)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.FUN)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.IF)] = .{ .prefix = null, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.NIL)] = .{ .prefix = Compiler.literal, .infix = null, .precedence = .NONE };
    r[@intFromEnum(TokenType.OR)] = .{ .prefix = null, .infix = Compiler.or_, .precedence = .OR };
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
