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
        throw new RuntimeError(expr.operator, "Operands must be two numbers or two strings.");
      case MINUS:
        checkNumberOperand(expr.operator, left, right);
        return (double) left - (double) right;
      case STAR:
        checkNumberOperand(expr.operator, left, right);
        return (double) left * (double) right;
      case SLASH:
        checkNumberOperand(expr.operator, left, right);
        return (double) left / (double) right;
      // Boolean.
      case GREATER:
        checkNumberOperand(expr.operator, left, right);
        return (double) left > (double) right;
      case GREATER_EQUAL:
        checkNumberOperand(expr.operator, left, right);
        return (double) left >= (double) right;
      case LESS:
        checkNumberOperand(expr.operator, left, right);
        return (double) left < (double) right;
      case LESS_EQUAL:
        checkNumberOperand(expr.operator, left, right);
        return (double) left <= (double) right;
      case BANG_EQUAL:
        return !isEqual(left, right);
      case EQUAL_EQUAL:
        return isEqual(left, right);
      default:
        throw new AssertionError();
    }
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
        checkNumberOperand(expr.operator, right);
        return -(double) right;
      default:
        throw new AssertionError();
    }
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

  private void checkNumberOperand(Token operator, Object operand) {
    if (operand instanceof Double) return;
    throw new RuntimeError(operator, "Operand must be a number.");
  }

  private void checkNumberOperand(Token operator, Object left, Object right) {
    if (left instanceof Double && right instanceof Double) return;
    throw new RuntimeError(operator, "Operands must be numbers.");
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

  private Object eval(Expr expr) {
    return expr.accept(this);
  }

  void interpret(Expr expression) {
    try {
      Object value = eval(expression);
      System.out.println(stringify(value));
    } catch (RuntimeError error) {
      Lox.runtimeError(error);
    }
  }

  private String stringify(Object object) {
    if (object == null) return "nil";
    String text = object.toString();
    if (object instanceof Double) {
      if (text.endsWith(".0")) {
        return text.substring(0, text.length() - 2);
      }
    }
    return text;
  }
}
