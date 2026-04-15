package com.cuongd.nanosystems.xlox;

import java.util.List;
import java.util.Map;

class XLoxClass implements XLoxCallable {
  final String name;
  private final Map<String, XLoxFunction> methods;

  XLoxClass(String name, Map<String, XLoxFunction> methods) {
    this.name = name;
    this.methods = methods;
  }

  XLoxFunction findMethod(String name) {
    if (methods.containsKey(name)) {
      return methods.get(name);
    }
    return null;
  }

  @Override
  public String toString() {
    return name;
  }

  @Override
  public int arity() {
    XLoxFunction initializer = findMethod("init");
    if (initializer == null) return 0;
    return initializer.arity();
  }

  @Override
  public Object call(Interpreter interpreter, List<Object> arguments) {
    XLoxInstance instance = new XLoxInstance(this);
    XLoxFunction initializer = findMethod("init");
    if (initializer != null) {
      initializer.bind(instance).call(interpreter, arguments);
    }
    return instance;
  }
}
