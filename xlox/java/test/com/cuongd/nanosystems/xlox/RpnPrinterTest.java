package com.cuongd.nanosystems.xlox;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

public class RpnPrinterTest {
  @Test
  public void binaryExpression() {
    assertEquals(
        "1 2 +", print(new Expr.Binary(new Expr.Literal(1), TestToken.PLUS, new Expr.Literal(2))));
  }

  @Test
  public void simple() {
    String actual =
        print(
            new Expr.Binary(
                new Expr.Grouping(
                    new Expr.Binary(
                        new Expr.Unary(TestToken.MINUS, new Expr.Literal(1)),
                        TestToken.PLUS,
                        new Expr.Literal(2))),
                TestToken.STAR,
                new Expr.Literal(3)));
    assertEquals("1 ~ 2 + 3 *", actual);
  }

  private String print(Expr expr) {
    return new RpnPrinter().print(expr);
  }
}
