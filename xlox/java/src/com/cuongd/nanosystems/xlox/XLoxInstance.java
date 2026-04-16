package com.cuongd.nanosystems.xlox;

import java.util.HashMap;
import java.util.Map;

class XLoxInstance {
  protected XLoxClass klass;
  protected final Map<String, Object> fields = new HashMap<>();

  XLoxInstance(XLoxClass klass) {
    this.klass = klass;
  }

  XLoxInstance() {} // For meta-classes.

  Object get(Token name) {
    if (fields.containsKey(name.lexeme)) {
      return fields.get(name.lexeme);
    }

    XLoxFunction method = klass.findMethod(name.lexeme);
    if (method != null) return method.bind(this);

    throw new RuntimeError(name, "Undefined property '" + name.lexeme + "'.");
  }

  void set(Token name, Object value) {
    fields.put(name.lexeme, value);
  }

  @Override
  public String toString() {
    return klass.name + " instance";
  }
}
