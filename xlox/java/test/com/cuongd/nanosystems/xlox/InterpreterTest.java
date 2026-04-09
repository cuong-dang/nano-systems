package com.cuongd.nanosystems.xlox;

import static org.junit.Assert.assertEquals;

import java.util.List;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

public class InterpreterTest {
  private static final Interpreter interpreter = new Interpreter();
  private static final Resolver resolver = new Resolver(interpreter);

  @Nested
  class Function {
    @Test
    public void anonymousFunction() {
      String script =
"""
fun invoke(fn) {
  return fn();
}
invoke(fun () { return 1; })
""";
      assertEquals(1.0, run(script));
    }

    @Test
    public void anonymousFunctionClosure() {
      String script =
"""
fun makeCounter(start) {
  var i = start;
  return fun () {
    i = i + 1;
    return i;
  };
}
var a = makeCounter(1);
a();
a()
""";
      assertEquals(3.0, run(script));
    }

    @Test
    public void noopAnonymousFunction() {
      String script =
"""
fun () {};
1
""";
      assertEquals(1.0, run(script));
    }

    @Test
    public void commaExpressionInFunctionCall() {
      String script =
"""
fun add(a, b) { return a + b; }
add(1, 2)
""";
      assertEquals(3.0, run(script));
    }
  }

  private static Object run(String s) {
    List<Stmt> statements = new Parser(new Scanner(s).scanTokens(), true).parse();
    resolver.resolve(statements);
    interpreter.interpret(statements);
    return interpreter.lastStatementResult();
  }
}
