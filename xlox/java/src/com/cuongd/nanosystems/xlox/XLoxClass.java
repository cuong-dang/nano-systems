package com.cuongd.nanosystems.xlox;

import java.util.List;
import java.util.Map;

class XLoxClass extends XLoxInstance implements XLoxCallable {
  final String name;
  final XLoxClass superclass;
  private final Map<String, XLoxFunction> instanceMethods;
  private final Map<String, XLoxFunction> classMethods;

  XLoxClass(
      String name,
      XLoxClass superclass,
      Map<String, XLoxFunction> instanceMethods,
      Map<String, XLoxFunction> classMethods) {
    this.name = name;
    this.superclass = superclass;
    this.instanceMethods = instanceMethods;
    this.classMethods = classMethods;
    this.klass = this;
  }

  XLoxFunction findMethod(String name) {
    if (instanceMethods.containsKey(name)) {
      return instanceMethods.get(name);
    }
    if (superclass != null) {
      return superclass.findMethod(name);
    }
    return null;
  }

  @Override
  Object get(Token name) {
    if (fields.containsKey(name.lexeme)) {
      return fields.get(name.lexeme);
    }

    if (classMethods.containsKey(name.lexeme)) {
      return classMethods.get(name.lexeme);
    }

    if (superclass != null) {
      return superclass.get(name);
    }

    throw new RuntimeError(name, "Undefined class method '" + name.lexeme + "'.");
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
