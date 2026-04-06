package com.cuongd.nanosystems.xlox;

import java.util.List;

interface XLoxCallable {
  int arity();

  Object call(Interpreter interpreter, List<Object> arguments);
}
