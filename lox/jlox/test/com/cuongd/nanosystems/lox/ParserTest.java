package com.cuongd.nanosystems.lox;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.util.Arrays;
import java.util.List;
import org.junit.jupiter.api.Test;

public class ParserTest {
  @Test
  public void primary() {
    assertRpn("1.0", Arrays.asList(TestToken.NUMBER1, TestToken.EOF));
  }

  @Test
  public void comma() {
    assertRpn(
        "1.0 2.0 +,3.0,",
        Arrays.asList(
            TestToken.NUMBER1,
            TestToken.PLUS,
            TestToken.NUMBER2,
            TestToken.COMMA,
            TestToken.NUMBER3,
            TestToken.EOF));
  }

  @Test
  public void ternary() {
    assertRpn(
        "1.0 2.0 3.0 4.0 5.0 ?: ?:",
        Arrays.asList(
            TestToken.NUMBER1,
            TestToken.QUESTION,
            TestToken.NUMBER2,
            TestToken.COLON,
            TestToken.NUMBER3,
            TestToken.QUESTION,
            TestToken.NUMBER4,
            TestToken.COLON,
            TestToken.NUMBER5,
            TestToken.EOF));
  }

  private void assertRpn(String expected, List<Token> tokens) {
    assertEquals(expected, new RpnPrinter().print(new Parser(tokens).parse()));
  }
}
