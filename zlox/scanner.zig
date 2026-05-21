const std = @import("std");

pub const Scanner = struct {
    _source: []const u8,
    _start: usize,
    _current: usize,
    _line: usize,

    pub fn init(source: []const u8) Scanner {
        return .{ ._source = source, ._start = 0, ._current = 0, ._line = 1 };
    }

    pub fn scanToken(self: *Scanner) Token {
        self.skipWhitespace();
        self._start = self._current;
        if (self.isAtEnd()) return self.makeToken(.EOF);

        const c = self.peek();
        self.advance();

        if (std.ascii.isDigit(c)) return self.number();

        switch (c) {
            '(' => return self.makeToken(.LEFT_PAREN),
            ')' => return self.makeToken(.RIGHT_PAREN),
            '{' => return self.makeToken(.LEFT_BRACE),
            '}' => return self.makeToken(.RIGHT_BRACE),
            ';' => return self.makeToken(.SEMICOLON),
            ',' => return self.makeToken(.COMMA),
            '.' => return self.makeToken(.DOT),
            '-' => return self.makeToken(.MINUS),
            '+' => return self.makeToken(.PLUS),
            '/' => return self.makeToken(.SLASH),
            '*' => return self.makeToken(.STAR),

            '!' => return self.makeToken(if (self.match('=')) .BANG_EQUAL else .BANG),
            '=' => return self.makeToken(if (self.match('=')) .EQUAL_EQUAL else .EQUAL),
            '<' => return self.makeToken(if (self.match('=')) .LESS_EQUAL else .LESS),
            '>' => return self.makeToken(if (self.match('=')) .GREATER_EQUAL else .GREATER),

            '"' => return self.string(),

            else => unreachable,
        }

        return self.errorToken("Unexpected character.");
    }

    fn isAtEnd(self: *const Scanner) bool {
        return self._current == self._source.len;
    }

    fn advance(self: *Scanner) void {
        self._current += 1;
    }

    fn peek(self: *const Scanner) u8 {
        if (self.isAtEnd()) return 0;
        return self._source[self._current];
    }

    fn peekNext(self: *const Scanner) u8 {
        if (self._current + 1 == self._source.len) return 0;
        return self._source[self._current + 1];
    }

    fn match(self: *Scanner, c: u8) bool {
        if (self.isAtEnd()) return false;
        if (self._source[self._current] != c) return false;
        self.advance();
        return true;
    }

    fn makeToken(self: *const Scanner, tokenType: TokenType) Token {
        return .{ .tokenType = tokenType, .lexeme = self._source[self._start..self._current], .line = self._line };
    }

    fn errorToken(self: *const Scanner, message: []const u8) Token {
        return .{ .tokenType = .ERROR, .lexeme = message, .line = self._line };
    }

    fn skipWhitespace(self: *Scanner) void {
        while (true) {
            const c = self.peek();
            switch (c) {
                ' ', '\r', '\t' => self.advance(),

                '\n' => {
                    self._line += 1;
                    self.advance();
                },

                '/' => if (self.peekNext() == '/') {
                    while (self.peek() != '\n' and !self.isAtEnd()) self.advance();
                } else {
                    return;
                },

                else => return,
            }
        }
    }

    fn number(self: *Scanner) Token {
        while (std.ascii.isDigit(self.peek())) self.advance();

        if (self.peek() == '.' and std.ascii.isDigit(self.peekNext())) {
            self.advance();
            while (std.ascii.isDigit(self.peek())) self.advance();
        }

        return self.makeToken(.NUMBER);
    }

    fn string(self: *Scanner) Token {
        while (self.peek() != '"' and !self.isAtEnd()) {
            if (self.peek() == '\n') self._line += 1;
            self.advance();
        }

        if (self.isAtEnd()) return self.errorToken("Unterminated string.");

        // The closing quote.
        self.advance();
        return self.makeToken(.STRING);
    }
};

pub const Token = struct {
    tokenType: TokenType,
    lexeme: []const u8,
    line: usize,
};

const TokenType = enum {
    // Single-character tokens.
    LEFT_PAREN,
    RIGHT_PAREN,
    LEFT_BRACE,
    RIGHT_BRACE,
    SEMICOLON,
    COMMA,
    DOT,
    MINUS,
    PLUS,
    SLASH,
    STAR,

    // One or two character tokens.
    BANG,
    BANG_EQUAL,
    EQUAL,
    EQUAL_EQUAL,
    GREATER,
    GREATER_EQUAL,
    LESS,
    LESS_EQUAL,

    // Literals.
    IDENTIFIER,
    STRING,
    NUMBER,

    // Keywords.
    AND,
    CLASS,
    ELSE,
    FALSE,
    FOR,
    FUN,
    IF,
    NIL,
    OR,
    PRINT,
    RETURN,
    SUPER,
    THIS,
    TRUE,
    VAR,
    WHILE,

    ERROR,
    EOF,
};
