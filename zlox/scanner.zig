const std = @import("std");

pub const Scanner = struct {
    source: []const u8,
    start: usize,
    current: usize,
    line: usize,

    pub fn init(source: []const u8) Scanner {
        return .{ .source = source, .start = 0, .current = 0, .line = 1 };
    }

    pub fn scanToken(self: *Scanner) Token {
        self.skipWhitespace();
        self.start = self.current;
        if (self.isAtEnd()) return self.makeToken(.EOF);

        const c = self.peek();
        self.advance();

        if (isAlpha(c)) return self.identifier();
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

            else => return self.errorToken("Unexpected character."),
        }
    }

    fn isAtEnd(self: *const Scanner) bool {
        return self.current == self.source.len;
    }

    fn advance(self: *Scanner) void {
        self.current += 1;
    }

    fn peek(self: *const Scanner) u8 {
        return if (self.isAtEnd()) 0 else self.source[self.current];
    }

    fn peekNext(self: *const Scanner) u8 {
        return if (self.current + 1 == self.source.len) 0 else self.source[self.current + 1];
    }

    fn match(self: *Scanner, c: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.source[self.current] != c) return false;
        self.advance();
        return true;
    }

    fn makeToken(self: *const Scanner, tokenType: TokenType) Token {
        return .{ .type = tokenType, .lexeme = self.source[self.start..self.current], .line = self.line };
    }

    fn errorToken(self: *const Scanner, message: []const u8) Token {
        return .{ .type = .ERROR, .lexeme = message, .line = self.line };
    }

    fn skipWhitespace(self: *Scanner) void {
        while (true) {
            const c = self.peek();
            switch (c) {
                ' ', '\r', '\t' => self.advance(),

                '\n' => {
                    self.line += 1;
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

    fn identifier(self: *Scanner) Token {
        while (isAlpha(self.peek()) or std.ascii.isDigit(self.peek())) self.advance();

        const identifierType: TokenType = switch (self.source[self.start]) {
            'a' => self.checkKeyword(1, "nd", .AND),
            'c' => self.checkKeyword(1, "lass", .CLASS),
            'e' => self.checkKeyword(1, "lse", .ELSE),
            'i' => self.checkKeyword(1, "f", .IF),
            'n' => self.checkKeyword(1, "il", .NIL),
            'o' => self.checkKeyword(1, "r", .OR),
            'p' => self.checkKeyword(1, "rint", .PRINT),
            'r' => self.checkKeyword(1, "eturn", .RETURN),
            's' => self.checkKeyword(1, "uper", .SUPER),
            'v' => self.checkKeyword(1, "ar", .VAR),
            'w' => self.checkKeyword(1, "hile", .WHILE),

            'f' => if (self.current - self.start > 1)
                switch (self.source[self.start + 1]) {
                    'a' => self.checkKeyword(2, "lse", .FALSE),
                    'o' => self.checkKeyword(2, "r", .FOR),
                    'u' => self.checkKeyword(2, "n", .FUN),
                    else => .IDENTIFIER,
                }
            else
                .IDENTIFIER,

            't' => if (self.current - self.start > 1)
                switch (self.source[self.start + 1]) {
                    'h' => self.checkKeyword(2, "is", .THIS),
                    'r' => self.checkKeyword(2, "ue", .TRUE),
                    else => .IDENTIFIER,
                }
            else
                .IDENTIFIER,
            else => .IDENTIFIER,
        };

        return self.makeToken(identifierType);
    }

    fn checkKeyword(self: *const Scanner, start: usize, rest: []const u8, tokenType: TokenType) TokenType {
        if (self.current - self.start - start == rest.len and
            std.mem.eql(u8, self.source[self.start + start .. self.current], rest))
        {
            return tokenType;
        }
        return .IDENTIFIER;
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
            if (self.peek() == '\n') self.line += 1;
            self.advance();
        }

        if (self.isAtEnd()) return self.errorToken("Unterminated string.");

        // The closing quote.
        self.advance();
        return self.makeToken(.STRING);
    }
};

pub const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    line: usize,
};

pub const TokenType = enum {
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

fn isAlpha(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}
