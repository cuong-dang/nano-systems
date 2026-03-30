package com.cuongd.nanosystems.lox;

import static com.cuongd.nanosystems.lox.TokenType.*;
import static org.junit.jupiter.api.Assertions.*;

import java.util.List;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

public class ScannerTest {
  @Nested
  class BlockComment {
    @Test
    void isIgnored() {
      List<Token> tks = scan("/* c */ var x = 1;");
      assertTokenTypes(tks, VAR, IDENTIFIER, EQUAL, NUMBER, SEMICOLON, EOF);
    }

    @Test
    void errorsIfNotTerminated() {
      Lox.clearError();
      scan("/*");
      assertEquals(true, Lox.inError());
    }

    @Test
    void advancesLines() {
      List<Token> tks = scan("/*\n*/\nvar x = 1;");
      assertEquals(3, tks.get(0).line);
    }

    @Test
    void isNested() {
      List<Token> tks = scan("/* /* */ */ var x = 1;");
      assertTokenTypes(tks, VAR, IDENTIFIER, EQUAL, NUMBER, SEMICOLON, EOF);
    }

    @Test
    void errorsIfNotTerminatedNesting() {
      Lox.clearError();
      scan("/* /* */");
      assertEquals(true, Lox.inError());
    }
  }

  @Nested
  class Expression {
    @Test
    void literal() {
      List<Token> tks = scan("1");
      assertTokenTypes(tks, NUMBER, EOF);
      assertTokenLexemes(tks, "1", "");
    }

    @Test
    void binaryAdd() {
      List<Token> tks = scan("1+1");
      assertTokenTypes(tks, NUMBER, PLUS, NUMBER, EOF);
      assertTokenLexemes(tks, "1", "+", "1", "");
    }

    @Test
    void comparison() {
      List<Token> tks = scan("1==1");
      assertTokenTypes(tks, NUMBER, EQUAL_EQUAL, NUMBER, EOF);
      assertTokenLexemes(tks, "1", "==", "1", "");
    }
  }

  private static List<Token> scan(String source) {
    return new Scanner(source).scanTokens();
  }

  private static void assertTokenTypes(List<Token> actual, TokenType... types) {
    assertEquals(types.length, actual.size());
    for (int i = 0; i < types.length; i++) {
      assertEquals(types[i], actual.get(i).type);
    }
  }

  private static void assertTokenLexemes(List<Token> actual, Object... values) {
    assertEquals(values.length, actual.size());
    for (int i = 0; i < values.length; i++) {
      assertEquals(values[i], actual.get(i).lexeme);
    }
  }
}
