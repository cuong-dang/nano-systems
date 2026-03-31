package com.cuongd.nanosystems.lox;

import com.cuongd.nanosystems.lox.Expr.Binary;
import com.cuongd.nanosystems.lox.Expr.Comma;
import com.cuongd.nanosystems.lox.Expr.Grouping;
import com.cuongd.nanosystems.lox.Expr.Literal;
import com.cuongd.nanosystems.lox.Expr.Ternary;
import com.cuongd.nanosystems.lox.Expr.Unary;

class Interpreter implements Expr.Visitor<Object> {

  @Override
  public Object visitBinaryExpr(Binary expr) {
    Object left = eval(expr.left);
    Object right = eval(expr.right);

    switch (expr.operator.type) {
      // Arithmetic.
      case PLUS:
        if (left instanceof Double && right instanceof Double) {
          return (double) left + (double) right;
        } else if (left instanceof String && right instanceof String) {
          return (String) left + (String) right;
        }
        break;
      case MINUS:
        return (double) left - (double) right;
      case STAR:
        return (double) left * (double) right;
      case SLASH:
        return (double) left / (double) right;
      // Boolean.
      case GREATER:
        return (double) left > (double) right;
      case GREATER_EQUAL:
        return (double) left >= (double) right;
      case LESS:
        return (double) left < (double) right;
      case LESS_EQUAL:
        return (double) left <= (double) right;
      case BANG_EQUAL:
        return !isEqual(left, right);
      case EQUAL_EQUAL:
        return isEqual(left, right);
    }
    throw new AssertionError();
  }

  @Override
  public Object visitGroupingExpr(Grouping expr) {
    return eval(expr.expression);
  }

  @Override
  public Object visitLiteralExpr(Literal expr) {
    return expr.value;
  }

  @Override
  public Object visitUnaryExpr(Unary expr) {
    Object right = eval(expr.right);

    switch (expr.operator.type) {
      case BANG:
        return !isTruthy(right);
      case MINUS:
        return -(double) right;
    }
    throw new AssertionError();
  }

  @Override
  public Object visitCommaExpr(Comma expr) {
    Object result = null;
    ;
    for (Expr e : expr.exprs) {
      result = eval(e);
    }
    return result;
  }

  @Override
  public Object visitTernaryExpr(Ternary expr) {
    if (isTruthy(eval(expr.cond))) {
      return eval(expr.yes);
    }
    return eval(expr.no);
  }

  // TODO: Maybe come back and revisit it to make it more like Python.
  private boolean isTruthy(Object object) {
    if (object == null) return false;
    if (object instanceof Boolean) return (boolean) object;
    return true;
  }

  private boolean isEqual(Object a, Object b) {
    if (a == null && b == null) return true;
    if (a == null) return false;

    return a.equals(b);
  }

  Object eval(Expr expr) {
    return expr.accept(this);
  }
}
