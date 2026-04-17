package com.cuongd.nanosystems.xlox;

import static com.cuongd.nanosystems.xlox.TokenType.AND;
import static com.cuongd.nanosystems.xlox.TokenType.BANG;
import static com.cuongd.nanosystems.xlox.TokenType.BANG_EQUAL;
import static com.cuongd.nanosystems.xlox.TokenType.BREAK;
import static com.cuongd.nanosystems.xlox.TokenType.CLASS;
import static com.cuongd.nanosystems.xlox.TokenType.COLON;
import static com.cuongd.nanosystems.xlox.TokenType.COMMA;
import static com.cuongd.nanosystems.xlox.TokenType.DOT;
import static com.cuongd.nanosystems.xlox.TokenType.ELSE;
import static com.cuongd.nanosystems.xlox.TokenType.EOF;
import static com.cuongd.nanosystems.xlox.TokenType.EQUAL;
import static com.cuongd.nanosystems.xlox.TokenType.EQUAL_EQUAL;
import static com.cuongd.nanosystems.xlox.TokenType.FALSE;
import static com.cuongd.nanosystems.xlox.TokenType.FOR;
import static com.cuongd.nanosystems.xlox.TokenType.FUN;
import static com.cuongd.nanosystems.xlox.TokenType.GREATER;
import static com.cuongd.nanosystems.xlox.TokenType.GREATER_EQUAL;
import static com.cuongd.nanosystems.xlox.TokenType.IDENTIFIER;
import static com.cuongd.nanosystems.xlox.TokenType.IF;
import static com.cuongd.nanosystems.xlox.TokenType.LEFT_BRACE;
import static com.cuongd.nanosystems.xlox.TokenType.LEFT_PAREN;
import static com.cuongd.nanosystems.xlox.TokenType.LESS;
import static com.cuongd.nanosystems.xlox.TokenType.LESS_EQUAL;
import static com.cuongd.nanosystems.xlox.TokenType.MINUS;
import static com.cuongd.nanosystems.xlox.TokenType.NIL;
import static com.cuongd.nanosystems.xlox.TokenType.NUMBER;
import static com.cuongd.nanosystems.xlox.TokenType.OR;
import static com.cuongd.nanosystems.xlox.TokenType.PLUS;
import static com.cuongd.nanosystems.xlox.TokenType.PRINT;
import static com.cuongd.nanosystems.xlox.TokenType.QUESTION;
import static com.cuongd.nanosystems.xlox.TokenType.RETURN;
import static com.cuongd.nanosystems.xlox.TokenType.RIGHT_BRACE;
import static com.cuongd.nanosystems.xlox.TokenType.RIGHT_PAREN;
import static com.cuongd.nanosystems.xlox.TokenType.SEMICOLON;
import static com.cuongd.nanosystems.xlox.TokenType.SLASH;
import static com.cuongd.nanosystems.xlox.TokenType.STAR;
import static com.cuongd.nanosystems.xlox.TokenType.STRING;
import static com.cuongd.nanosystems.xlox.TokenType.THIS;
import static com.cuongd.nanosystems.xlox.TokenType.TRUE;
import static com.cuongd.nanosystems.xlox.TokenType.VAR;
import static com.cuongd.nanosystems.xlox.TokenType.WHILE;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.function.Supplier;

class Parser {
  private final List<Token> tokens;
  private final boolean replMode;
  private int current = 0;
  private int loopDepth = 0;
  private boolean inClassDeclaration;

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
      if (matchAny(CLASS)) return classDeclaration();
      if (check(FUN) && checkNext(IDENTIFIER)) {
        consume(FUN, null);
        return function("function");
      }
      if (matchAny(VAR)) return varDeclaration();

      return statement();
    } catch (ParseError error) {
      synchronize();
      return null;
    }
  }

  private Stmt classDeclaration() {
    boolean enclosingInClassDeclaration = inClassDeclaration;
    inClassDeclaration = true;

    Token name = consume(IDENTIFIER, "Expect class name.");
    consume(LEFT_BRACE, "Expect '{' before class body.");
    List<Stmt.Function> methods = new ArrayList<>();
    while (!check(RIGHT_BRACE) && !isAtEnd()) {
      if (matchAny(CLASS)) {
        methods.add(function("class"));
      } else {
        methods.add(function("method"));
      }
    }
    consume(RIGHT_BRACE, "Expect '}' after class body.");

    inClassDeclaration = enclosingInClassDeclaration;

    return new Stmt.Class(name, methods);
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
    if (matchAny(LEFT_BRACE)) return new Stmt.Block(block());
    if (matchAny(BREAK)) return breakStatement();
    if (matchAny(FOR)) return forStatement();
    if (matchAny(IF)) return ifStatement();
    if (matchAny(PRINT)) return printStatement();
    if (matchAny(RETURN)) return returnStatement();
    if (matchAny(WHILE)) return whileStatement();

    return expressionStatement();
  }

  private List<Stmt> block() {
    List<Stmt> statements = new ArrayList<>();

    while (!check(RIGHT_BRACE) && !isAtEnd()) {
      statements.add(declaration());
    }
    consume(RIGHT_BRACE, "Expect '}' after block.");
    return statements;
  }

  private Stmt breakStatement() {
    if (loopDepth == 0) {
      error(previous(), "Break statement not in a loop.");
    }
    consume(SEMICOLON, "Expect ';' after break.");
    return new Stmt.Break();
  }

  private Stmt forStatement() {
    try {
      loopDepth++;
      // Parse statement.
      consume(LEFT_PAREN, "Expect '(' after 'for'.");
      Stmt initializer = null;
      if (matchAny(VAR)) {
        initializer = varDeclaration();
      } else if (!matchAny(SEMICOLON)) {
        initializer = expressionStatement();
      }
      Expr condition = null;
      if (!check(SEMICOLON)) {
        condition = expression();
      }
      consume(SEMICOLON, "Expect ';' after for-loop condition.");
      Expr increment = null;
      if (!check(RIGHT_PAREN)) {
        increment = expression();
      }
      consume(RIGHT_PAREN, "Expect ')' after for-loop increment.");
      Stmt body = statement();

      // Desugar to a while-loop.
      if (increment != null) {
        body = new Stmt.Block(Arrays.asList(body, new Stmt.Expression(increment)));
      }
      if (condition == null) condition = new Expr.Literal(true);
      body = new Stmt.While(condition, body);
      if (initializer != null) {
        body = new Stmt.Block(Arrays.asList(initializer, body));
      }
      return body;
    } finally {
      loopDepth--;
    }
  }

  private Stmt ifStatement() {
    consume(LEFT_PAREN, "Expect '(' after 'if'.");
    Expr condition = expression();
    consume(RIGHT_PAREN, "Expect ')' after if condition.");
    Stmt thenBranch = statement();
    Stmt elseBranch = null;
    if (matchAny(ELSE)) {
      elseBranch = statement();
    }
    return new Stmt.If(condition, thenBranch, elseBranch);
  }

  private Stmt printStatement() {
    Expr expr = expression();
    consume(SEMICOLON, "Expect ';' after statement.");
    return new Stmt.Print(expr);
  }

  private Stmt returnStatement() {
    Token keyword = previous();
    Expr value = null;
    if (!check(SEMICOLON)) {
      value = expression();
    }
    consume(SEMICOLON, "Expect ';' after return value.");
    return new Stmt.Return(keyword, value);
  }

  private Stmt whileStatement() {
    try {
      loopDepth++;
      consume(LEFT_PAREN, "Expect '(' after 'while'.");
      Expr condition = expression();
      consume(RIGHT_PAREN, "Expect ')' after while condition.");
      Stmt body = statement();
      return new Stmt.While(condition, body);
    } finally {
      loopDepth--;
    }
  }

  private Stmt expressionStatement() {
    Expr expr = expression();
    consume(SEMICOLON, "Expect ';' after statement.");
    return new Stmt.Expression(expr);
  }

  private Stmt.Function function(String kind) {
    Token name = consume(IDENTIFIER, "Expect " + kind + " name.");
    if (inClassDeclaration && !kind.equals("class") && !check(LEFT_PAREN)) {
      kind = "getter";
    }
    return new Stmt.Function(name, lambda(kind.equals("getter")), kind);
  }

  private Expr expression() {
    return comma();
  }

  private Expr comma() {
    List<Expr> exprs = new ArrayList<>();
    do {
      exprs.add(ternary());
    } while (matchAny(COMMA));
    return exprs.size() == 1 ? exprs.get(0) : new Expr.Comma(exprs);
  }

  private Expr ternary() {
    Expr expr = assignment();
    if (matchAny(QUESTION)) {
      Expr yes = ternary();
      consume(COLON, "Expect ':' in ternary expression.");
      Expr no = ternary();
      return new Expr.Ternary(expr, yes, no);
    }
    return expr;
  }

  private Expr assignment() {
    Expr expr = or();

    if (matchAny(EQUAL)) {
      Token equals = previous();
      Expr value = assignment();

      if (expr instanceof Expr.Variable) {
        Token name = ((Expr.Variable) expr).name;
        return new Expr.Assign(name, value);
      } else if (expr instanceof Expr.Get) {
        Expr.Get get = (Expr.Get) expr;
        return new Expr.Set(get.object, get.name, value);
      }

      error(equals, "Invalid assignment target.");
    }

    return expr;
  }

  private Expr or() {
    Expr expr = and();

    while (matchAny(OR)) {
      Token operator = previous();
      Expr right = and();
      expr = new Expr.Logical(expr, operator, right);
    }

    return expr;
  }

  private Expr and() {
    Expr expr = equality();

    while (matchAny(AND)) {
      Token operator = previous();
      Expr right = equality();
      expr = new Expr.Logical(expr, operator, right);
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

    return call();
  }

  private Expr call() {
    Expr expr = primary();

    while (true) {
      if (matchAny(LEFT_PAREN)) {
        expr = finishCall(expr);
      } else if (matchAny(DOT)) {
        Token name = consume(IDENTIFIER, "Expect property name after '.'.");
        expr = new Expr.Get(expr, name);
      } else {
        break;
      }
    }

    return expr;
  }

  private Expr finishCall(Expr callee) {
    List<Expr> arguments = new ArrayList<>();
    if (!check(RIGHT_PAREN)) {
      do {
        if (arguments.size() >= 255) {
          error(peek(), "Can't have more than 255 arguments.");
        }
        arguments.add(ternary());
      } while (matchAny(COMMA));
    }

    Token paren = consume(RIGHT_PAREN, "Expect ')' after arguments.");

    return new Expr.Call(callee, paren, arguments);
  }

  private Expr primary() {
    if (matchAny(FUN)) return lambda(false);
    if (matchAny(FALSE)) return new Expr.Literal(false);
    if (matchAny(TRUE)) return new Expr.Literal(true);
    if (matchAny(NIL)) return new Expr.Literal(null);
    if (matchAny(THIS)) return new Expr.This(previous());

    if (matchAny(NUMBER, STRING)) return new Expr.Literal(previous().literal);

    if (matchAny(IDENTIFIER)) return new Expr.Variable(previous());

    if (matchAny(LEFT_PAREN)) {
      Expr expr = expression();
      consume(RIGHT_PAREN, "Expect ')' after expression.");
      return new Expr.Grouping(expr);
    }

    throw error(peek(), "Expect expression.");
  }

  private Expr.Lambda lambda(boolean isGetter) {
    List<Token> parameters = new ArrayList<>();

    if (!isGetter) {
      consume(LEFT_PAREN, "Expect '(' after lambda.");
      if (!check(RIGHT_PAREN)) {
        do {
          if (parameters.size() >= 255) {
            error(peek(), "Can't have more than 255 parameters.");
          }

          parameters.add(consume(IDENTIFIER, "Expect parameter name."));
        } while (matchAny(COMMA));
      }
      consume(RIGHT_PAREN, "Expect ')' after parameters.");
    }
    consume(LEFT_BRACE, "Expect '{' before lambda body.");
    List<Stmt> body = block();
    return new Expr.Lambda(parameters, body);
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

  private boolean checkNext(TokenType type) {
    if (isAtEnd()) return false;
    return tokens.get(current + 1).type == type;
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
