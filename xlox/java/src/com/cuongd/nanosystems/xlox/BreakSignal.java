package com.cuongd.nanosystems.xlox;

class BreakSignal extends RuntimeException {
  BreakSignal() {
    super(null, null, false, false);
  }
}
