package com.cuongd.nanosystems.lox;

import static com.cuongd.nanosystems.lox.TokenType.MINUS;
import static com.cuongd.nanosystems.lox.TokenType.PLUS;
import static com.cuongd.nanosystems.lox.TokenType.STAR;
import static org.junit.Assert.assertEquals;

import org.junit.Test;

public class RpnPrinterTest {
  @Test
  public void binaryExpression() {
    assertEquals(
        "1 2 +",
        print(
            new Expr.Binary(
                new Expr.Literal(1), new Token(PLUS, "+", null, 1), new Expr.Literal(2))));
  }

  @Test
  public void simple() {
    String actual =
        print(
            new Expr.Binary(
                new Expr.Grouping(
                    new Expr.Binary(
                        new Expr.Unary(new Token(MINUS, "-", null, 1), new Expr.Literal(1)),
                        new Token(PLUS, "+", null, 1),
                        new Expr.Literal(2))),
                new Token(STAR, "*", null, 0),
                new Expr.Literal(3)));
    assertEquals("1 ~ 2 + 3 *", actual);
  }

  private String print(Expr expr) {
    return new RpnPrinter().print(expr);
  }
}
