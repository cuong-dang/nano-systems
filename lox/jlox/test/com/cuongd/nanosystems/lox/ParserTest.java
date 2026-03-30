package com.cuongd.nanosystems.lox;

import static com.cuongd.nanosystems.lox.TokenType.*;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;

import java.util.Arrays;
import org.junit.Test;

public class ParserTest {
  @Test
  public void primary() {
    Expr parsed = new Parser(Arrays.asList(new Token(NUMBER, "1", 1.0, 0))).parse();
    assertInstanceOf(Expr.Literal.class, parsed);
  }
}
