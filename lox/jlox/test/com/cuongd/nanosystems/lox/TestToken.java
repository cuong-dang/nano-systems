package com.cuongd.nanosystems.lox;

class TestToken {
  static final Token PLUS = new Token(TokenType.PLUS, "+", null, 0);
  static final Token MINUS = new Token(TokenType.MINUS, "-", null, 0);
  static final Token STAR = new Token(TokenType.STAR, "*", null, 0);
  static final Token NUMBER1 = new Token(TokenType.NUMBER, "1", 1.0, 0);
  static final Token NUMBER2 = new Token(TokenType.NUMBER, "2", 2.0, 0);
  static final Token NUMBER3 = new Token(TokenType.NUMBER, "3", 3.0, 0);
  static final Token COMMA = new Token(TokenType.COMMA, ",", null, 0);
  static final Token EOF = new Token(TokenType.EOF, "", null, 0);
}
