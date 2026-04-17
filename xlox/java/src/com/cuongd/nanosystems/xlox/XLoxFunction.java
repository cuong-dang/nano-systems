package com.cuongd.nanosystems.xlox;

import java.util.List;

class XLoxFunction implements XLoxCallable {
  enum Type {
    PLAIN,
    INITIALIZER,
    GETTER,
  }

  private final Stmt.Function declaration;
  private final Environment closure;
  private final Type type;

  XLoxFunction(Stmt.Function declaration, Environment closure, Type type) {
    this.declaration = declaration;
    this.closure = closure;
    this.type = type;
  }

  XLoxFunction bind(XLoxInstance instance) {
    Environment environment = new Environment(closure);
    environment.define("this", instance);
    return new XLoxFunction(declaration, environment, type);
  }

  public boolean isGetter() {
    return type == Type.GETTER;
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
      if (type == Type.INITIALIZER) return closure.getAt(0, "this");
      return r.value;
    }

    if (type == Type.INITIALIZER) return closure.getAt(0, "this");
    return null;
  }

  @Override
  public String toString() {
    return declaration.name == null ? "<lambda>" : "<fn " + declaration.name.lexeme + ">";
  }
}
