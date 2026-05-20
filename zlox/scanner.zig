pub const Scanner = struct {
    _start: []const u8,
    _current: usize,
    _line: usize,

    pub fn init(source: []const u8) Scanner {
        return .{ ._start = source, ._current = 0, ._line = 1 };
    }

    pub fn scanToken(self: *Scanner) Token {
        self._start = self._start[self._current..];
        self._current = 0;
        if (self.isAtEnd()) return self.makeToken(.EOF);

        const c = self.advance();

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
            else => unreachable,
        }

        return self.errorToken("Unexpected character.");
    }

    fn isAtEnd(self: *const Scanner) bool {
        return self._start.len == 0;
    }

    fn advance(self: *Scanner) u8 {
        self._current += 1;
        return self._start[self._current - 1];
    }

    fn makeToken(self: *const Scanner, tokenType: TokenType) Token {
        return .{ .tokenType = tokenType, .lexeme = self._start[0..self._current], .line = self._line };
    }

    fn errorToken(self: *const Scanner, message: []const u8) Token {
        return .{ .tokenType = .ERROR, .lexeme = message, .line = self._line };
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
    COMMA,
    DOT,
    MINUS,
    PLUS,
    SEMICOLON,
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
