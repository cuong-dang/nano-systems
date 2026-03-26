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

  private static List<Token> scan(String source) {
    return new Scanner(source).scanTokens();
  }

  private static void assertTokenTypes(List<Token> actual, TokenType... types) {
    assertEquals(types.length, actual.size());
    for (int i = 0; i < types.length; i++) {
      assertEquals(types[i], actual.get(i).type);
    }
  }
}
