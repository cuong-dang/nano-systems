package com.cuongd.nanosystems.xlox;

import static com.cuongd.nanosystems.xlox.TokenType.*;

import java.util.ArrayList;
import java.util.List;
import java.util.function.Supplier;

class Parser {
  private final List<Token> tokens;
  private final boolean replMode;
  private int current = 0;

  Parser(List<Token> tokens, boolean replMode) {
    this.tokens = tokens;
    this.replMode = replMode;
  }

  List<Stmt> parse() {
    List<Stmt> statements = new ArrayList<>();
    while (!isAtEnd()) {
      statements.add(declaration());
    }
    return statements;
  }

  private Stmt declaration() {
    try {
      if (matchAny(VAR)) return varDeclaration();

      return statement();
    } catch (ParseError error) {
      synchronize();
      return null;
    }
  }

  private Stmt varDeclaration() {
    Token name = consume(IDENTIFIER, "Expect variable name.");
    Expr initializer = null;
    if (matchAny(EQUAL)) {
      initializer = expression();
    }
    consume(SEMICOLON, "Expect ';' after variable declaration.");
    return new Stmt.Var(name, initializer);
  }

  private Stmt statement() {
    if (matchAny(PRINT)) return printStatement();

    return expressionStatement();
  }

  private Stmt printStatement() {
    Expr expr = expression();
    consume(SEMICOLON, "Expect ';' after statement.");
    return new Stmt.Print(expr);
  }

  private Stmt expressionStatement() {
    Expr expr = expression();
    consume(SEMICOLON, "Expect ';' after statement.");
    return new Stmt.Expression(expr);
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
    do {
      exprs.add(assignment());
    } while (matchAny(COMMA));
    return exprs.size() == 1 ? exprs.get(0) : new Expr.Comma(exprs);
  }

  private Expr assignment() {
    Expr expr = equality();

    if (matchAny(EQUAL)) {
      Token equals = previous();
      Expr value = assignment();

      if (expr instanceof Expr.Variable) {
        Token name = ((Expr.Variable) expr).name;
        return new Expr.Assign(name, value);
      }

      error(equals, "Invalid assignment target.");
    }

    return expr;
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

    if (matchAny(IDENTIFIER)) return new Expr.Variable(previous());

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

  private boolean matchAny(TokenType... types) {
    for (TokenType type : types) {
      if (check(type)) {
        advance();
        return true;
      }
    }
    return false;
  }

  private Token advance() {
    if (!isAtEnd()) current++;
    return previous();
  }

  private Token consume(TokenType type, String message) {
    // Special case for SEMICOLON in REPL mode.
    if (type == SEMICOLON && replMode && isAtEnd()) return advance();
    if (check(type)) return advance();
    throw error(peek(), message);
  }

  private boolean check(TokenType type) {
    if (isAtEnd()) return false;
    return peek().type == type;
  }

  // TODO: Revisit this error processing and handling.
  private ParseError error(Token token, String message) {
    XLox.error(token, message);
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

  static class ParseError extends RuntimeException {}
}
