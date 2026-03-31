package com.cuongd.nanosystems.lox;

import static com.cuongd.nanosystems.lox.TokenType.BANG;
import static com.cuongd.nanosystems.lox.TokenType.BANG_EQUAL;
import static com.cuongd.nanosystems.lox.TokenType.COLON;
import static com.cuongd.nanosystems.lox.TokenType.COMMA;
import static com.cuongd.nanosystems.lox.TokenType.EOF;
import static com.cuongd.nanosystems.lox.TokenType.EQUAL_EQUAL;
import static com.cuongd.nanosystems.lox.TokenType.FALSE;
import static com.cuongd.nanosystems.lox.TokenType.GREATER;
import static com.cuongd.nanosystems.lox.TokenType.GREATER_EQUAL;
import static com.cuongd.nanosystems.lox.TokenType.LEFT_PAREN;
import static com.cuongd.nanosystems.lox.TokenType.LESS;
import static com.cuongd.nanosystems.lox.TokenType.LESS_EQUAL;
import static com.cuongd.nanosystems.lox.TokenType.MINUS;
import static com.cuongd.nanosystems.lox.TokenType.NIL;
import static com.cuongd.nanosystems.lox.TokenType.NUMBER;
import static com.cuongd.nanosystems.lox.TokenType.PLUS;
import static com.cuongd.nanosystems.lox.TokenType.QUESTION;
import static com.cuongd.nanosystems.lox.TokenType.RIGHT_PAREN;
import static com.cuongd.nanosystems.lox.TokenType.SEMICOLON;
import static com.cuongd.nanosystems.lox.TokenType.SLASH;
import static com.cuongd.nanosystems.lox.TokenType.STAR;
import static com.cuongd.nanosystems.lox.TokenType.STRING;
import static com.cuongd.nanosystems.lox.TokenType.TRUE;

import java.util.ArrayList;
import java.util.List;
import java.util.function.Supplier;

class Parser {
  private final List<Token> tokens;
  private int current = 0;

  Parser(List<Token> tokens) {
    this.tokens = tokens;
  }

  Expr parse() {
    try {
      return expression();
    } catch (ParseError error) {
      return null;
    }
  }

  private Expr expression() {
    return ternary();
  }

  private Expr ternary() {
    Expr expr = comma();
    if (matchAny(QUESTION)) {
      Expr yes = ternary();
      consume(COLON, "Expect ':' in ternary expression.");
      Expr no = ternary();
      return new Expr.Ternary(expr, yes, no);
    }
    return expr;
  }

  private Expr comma() {
    List<Expr> exprs = new ArrayList<>();
    exprs.add(equality());
    while (matchAny(COMMA)) {
      exprs.add(equality());
    }
    return exprs.size() == 1 ? exprs.get(0) : new Expr.Comma(exprs);
  }

  private Expr equality() {
    return binaryHelper(this::comparison, BANG_EQUAL, EQUAL_EQUAL);
  }

  private Expr comparison() {
    return binaryHelper(this::term, GREATER, GREATER_EQUAL, LESS, LESS_EQUAL);
  }

  private Expr term() {
    return binaryHelper(this::factor, PLUS, MINUS);
  }

  private Expr factor() {
    return binaryHelper(this::unary, STAR, SLASH);
  }

  private Expr unary() {
    if (matchAny(BANG, MINUS)) {
      return new Expr.Unary(previous(), unary());
    }
    return primary();
  }

  private Expr primary() {
    if (matchAny(FALSE)) return new Expr.Literal(false);
    if (matchAny(TRUE)) return new Expr.Literal(true);
    if (matchAny(NIL)) return new Expr.Literal(null);

    if (matchAny(NUMBER, STRING)) return new Expr.Literal(previous().literal);

    if (matchAny(LEFT_PAREN)) {
      Expr expr = expression();
      consume(RIGHT_PAREN, "Expect ')' after expression.");
      return new Expr.Grouping(expr);
    }

    throw error(peek(), "Expect expression.");
  }

  private Expr binaryHelper(Supplier<Expr> next, TokenType... types) {
    Expr expr = next.get();

    while (matchAny(types)) {
      Token operator = previous();
      Expr right = next.get();
      expr = new Expr.Binary(expr, operator, right);
    }
    return expr;
  }

  private boolean isAtEnd() {
    return peek().type == EOF;
  }

  private Token peek() {
    return tokens.get(current);
  }

  private Token previous() {
    return tokens.get(current - 1);
  }

  private Token advance() {
    if (!isAtEnd()) current++;
    return previous();
  }

  private Token consume(TokenType type, String message) {
    if (check(type)) return advance();
    throw error(peek(), message);
  }

  private boolean matchAny(TokenType... types) {
    for (TokenType type : types) {
      if (check(type)) {
        advance();
        return true;
      }
    }
    return false;
  }

  private boolean check(TokenType type) {
    if (isAtEnd()) return false;
    return peek().type == type;
  }

  // TODO: Revisit this error processing and handling.
  private ParseError error(Token token, String message) {
    Lox.error(token, message);
    return new ParseError();
  }

  private void synchronize() {
    advance();

    while (!isAtEnd()) {
      if (previous().type == SEMICOLON) return;

      switch (peek().type) {
        case CLASS:
        case FUN:
        case VAR:
        case FOR:
        case IF:
        case WHILE:
        case PRINT:
        case RETURN:
          return;
      }

      advance();
    }
  }

  private static class ParseError extends RuntimeException {}
}
