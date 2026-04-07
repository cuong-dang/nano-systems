package com.cuongd.nanosystems.xlox;

import java.util.List;

class XLoxFunction implements XLoxCallable {
  private final Stmt.Function declaration;
  private final Environment closure;

  XLoxFunction(Stmt.Function declaration, Environment closure) {
    this.declaration = declaration;
    this.closure = closure;
  }

  @Override
  public int arity() {
    return declaration.lambda.params.size();
  }

  @Override
  public Object call(Interpreter interpreter, List<Object> arguments) {
    Environment environment = new Environment(closure);
    for (int i = 0; i < declaration.lambda.params.size(); i++) {
      environment.define(declaration.lambda.params.get(i).lexeme, arguments.get(i));
    }

    try {
      interpreter.executeBlock(declaration.lambda.body, environment);
    } catch (Return r) {
      return r.value;
    }
    return null;
  }

  @Override
  public String toString() {
    return declaration.name == null ? "<lambda>" : "<fn " + declaration.name.lexeme + ">";
  }
}
