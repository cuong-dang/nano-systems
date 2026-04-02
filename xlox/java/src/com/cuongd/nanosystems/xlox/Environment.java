package com.cuongd.nanosystems.xlox;

import java.util.HashMap;
import java.util.Map;

class Environment {
  private final Environment enclosing;
  private final Map<String, Object> values = new HashMap<>();

  Environment() {
    this.enclosing = null;
  }

  Environment(Environment enclosing) {
    this.enclosing = enclosing;
  }

  void define(String name, Object value) {
    values.put(name, value);
  }

  void assign(Token name, Object value) {
    if (isDefinedHere(name)) values.put(name.lexeme, value);
    else if (enclosing != null) enclosing.assign(name, value);
    else notDefinedError(name);
  }

  Object get(Token name) {
    if (isDefinedHere(name)) return values.get(name.lexeme);
    if (enclosing != null) return enclosing.get(name);
    notDefinedError(name);
    throw new AssertionError(); // Unreachable.
  }

  private void notDefinedError(Token name) {
    throw new RuntimeError(name, "Undefined variable '" + name.lexeme + "'.");
  }

  boolean isDefinedHere(Token name) {
    return values.containsKey(name.lexeme);
  }
}
