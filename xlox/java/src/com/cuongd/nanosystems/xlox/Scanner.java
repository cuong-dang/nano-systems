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
import static com.cuongd.nanosystems.xlox.TokenType.SUPER;
import static com.cuongd.nanosystems.xlox.TokenType.THIS;
import static com.cuongd.nanosystems.xlox.TokenType.TRUE;
import static com.cuongd.nanosystems.xlox.TokenType.VAR;
import static com.cuongd.nanosystems.xlox.TokenType.WHILE;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

class Scanner {
  private final String source;
  private final List<Token> tokens = new ArrayList<>();
  private int start = 0;
  private int current = 0;
  private int line = 1;

  private static final Map<String, TokenType> keywords;

  static {
    keywords = new HashMap<>();
    keywords.put("and", AND);
    keywords.put("break", BREAK);
    keywords.put("class", CLASS);
    keywords.put("else", ELSE);
    keywords.put("false", FALSE);
    keywords.put("for", FOR);
    keywords.put("fun", FUN);
    keywords.put("if", IF);
    keywords.put("nil", NIL);
    keywords.put("or", OR);
    keywords.put("print", PRINT);
    keywords.put("return", RETURN);
    keywords.put("super", SUPER);
    keywords.put("this", THIS);
    keywords.put("true", TRUE);
    keywords.put("var", VAR);
    keywords.put("while", WHILE);
  }

  Scanner(String source) {
    this.source = source;
  }

  List<Token> scanTokens() {
    while (!isAtEnd()) {
      start = current;
      scanToken();
    }

    tokens.add(new Token(EOF, "", null, line));
    return tokens;
  }

  private void scanToken() {
    char c = advance();
    switch (c) {
      case '(':
        addToken(LEFT_PAREN);
        break;
      case ')':
        addToken(RIGHT_PAREN);
        break;
      case '{':
        addToken(LEFT_BRACE);
        break;
      case '}':
        addToken(RIGHT_BRACE);
        break;
      case ',':
        addToken(COMMA);
        break;
      case '.':
        addToken(DOT);
        break;
      case '-':
        addToken(MINUS);
        break;
      case '+':
        addToken(PLUS);
        break;
      case ';':
        addToken(SEMICOLON);
        break;
      case '*':
        addToken(STAR);
        break;
      case '?':
        addToken(QUESTION);
        break;
      case ':':
        addToken(COLON);
        break;

      case '!':
        addToken(match('=') ? BANG_EQUAL : BANG);
        break;
      case '=':
        addToken(match('=') ? EQUAL_EQUAL : EQUAL);
        break;
      case '>':
        addToken(match('=') ? GREATER_EQUAL : GREATER);
        break;
      case '<':
        addToken(match('=') ? LESS_EQUAL : LESS);
        break;
      case '/':
        if (match('/')) {
          while (peek() != '\n' && !isAtEnd()) advance();
        } else if (match('*')) {
          int nesting = 1;
          while (nesting > 0) {
            if (isAtEnd()) {
              XLox.error(nesting, "Unterminated block comment.");
              return;
            }
            if (peek() == '/' && peekNext() == '*') {
              nesting++;
              advance();
              advance();
              continue;
            }
            if (peek() == '*' && peekNext() == '/') {
              nesting--;
              advance();
              advance();
              continue;
            }
            if (peek() == '\n') line++;
            advance();
          }
        } else {
          addToken(SLASH);
        }
        break;

      case ' ':
      case '\r':
      case '\t':
        break;
      case '\n':
        line++;
        break;

      case '"':
        string();
        break;
      default:
        if (isDigit(c)) {
          number();
        } else if (isAlpha(c)) {
          identifier();
        } else {
          XLox.error(line, "Unexpected character.");
        }
        break;
    }
  }

  private void string() {
    while (peek() != '"' && !isAtEnd()) {
      if (peek() == '\n') line++;
      advance();
    }

    if (isAtEnd()) {
      XLox.error(line, "Unterminated string.");
      return;
    }

    // The closing ".
    advance();

    String value = source.substring(start + 1, current - 1);
    addToken(STRING, value);
  }

  private void number() {
    while (isDigit(peek())) advance();

    if (peek() == '.' && isDigit(peekNext())) {
      // Consume the '.'.
      advance();
      while (isDigit(peek())) advance();
    }

    Double value = Double.parseDouble(source.substring(start, current));
    addToken(NUMBER, value);
  }

  private void identifier() {
    while (isAlphaNumeric(peek())) advance();

    String text = source.substring(start, current);
    TokenType type = keywords.getOrDefault(text, IDENTIFIER);
    addToken(type);
  }

  private boolean isDigit(char c) {
    return c >= '0' && c <= '9';
  }

  private boolean isAlpha(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c == '_');
  }

  private boolean isAlphaNumeric(char c) {
    return isAlpha(c) || isDigit(c);
  }

  private boolean match(char expected) {
    if (isAtEnd()) return false;
    if (source.charAt(current) != expected) return false;

    advance();
    return true;
  }

  private boolean isAtEnd() {
    return current >= source.length();
  }

  private char advance() {
    return source.charAt(current++);
  }

  private char peek() {
    if (isAtEnd()) return '\0';
    return source.charAt(current);
  }

  private char peekNext() {
    if (current + 1 >= source.length()) return '\0';
    return source.charAt(current + 1);
  }

  private void addToken(TokenType type, Object literal) {
    String text = source.substring(start, current);
    tokens.add(new Token(type, text, literal, line));
  }

  private void addToken(TokenType type) {
    addToken(type, null);
  }
}
