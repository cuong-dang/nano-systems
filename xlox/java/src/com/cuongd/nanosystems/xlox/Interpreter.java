package com.cuongd.nanosystems.xlox;

import com.cuongd.nanosystems.xlox.Expr.Binary;
import com.cuongd.nanosystems.xlox.Expr.Comma;
import com.cuongd.nanosystems.xlox.Expr.Grouping;
import com.cuongd.nanosystems.xlox.Expr.Literal;
import com.cuongd.nanosystems.xlox.Expr.Ternary;
import com.cuongd.nanosystems.xlox.Expr.Unary;
import com.cuongd.nanosystems.xlox.Stmt.Expression;
import com.cuongd.nanosystems.xlox.Stmt.Print;
import java.util.List;

class Interpreter implements Expr.Visitor<Object>, Stmt.Visitor<Object> {
  private Object lastStatementResult;

  @Override
  public Object visitBinaryExpr(Binary expr) {
    Object left = eval(expr.left);
    Object right = eval(expr.right);
    double leftDouble = left instanceof Double ? (double) left : null;
    double rightDouble = right instanceof Double ? (double) right : null;
    String leftString = left instanceof String ? (String) left : null;
    String rightString = right instanceof String ? (String) right : null;

    switch (expr.operator.type) {
      // Arithmetic.
      case PLUS:
        if (left instanceof Double && right instanceof Double) {
          return leftDouble + rightDouble;
        } else if (left instanceof String && right instanceof String) {
          return leftString + rightString;
        }
        throw new RuntimeError(expr.operator, "Operands must be two numbers or two strings.");
      case MINUS:
        checkNumberOperand(expr.operator, left, right);
        return leftDouble - rightDouble;
      case STAR:
        checkNumberOperand(expr.operator, left, right);
        return leftDouble * rightDouble;
      case SLASH:
        checkNumberOperand(expr.operator, left, right);
        // TODO: Can throw runtime error here if division by zero with two ints.
        //   This would probably require to represent numbers as ints as well.
        return leftDouble / rightDouble;
      // Boolean.
      case GREATER:
        if (left instanceof Double && right instanceof Double) {
          return Double.compare(leftDouble, rightDouble) > 0;
        } else if (left instanceof String && right instanceof String) {
          return (leftString).compareTo(rightString) > 0;
        }
        throw new RuntimeError(expr.operator, "Operands must be two numbers or two strings.");
      case GREATER_EQUAL:
        if (left instanceof Double && right instanceof Double) {
          return Double.compare(leftDouble, rightDouble) >= 0;
        } else if (left instanceof String && right instanceof String) {
          return (leftString).compareTo(rightString) >= 0;
        }
        throw new RuntimeError(expr.operator, "Operands must be two numbers or two strings.");
      case LESS:
        if (left instanceof Double && right instanceof Double) {
          return Double.compare(leftDouble, rightDouble) < 0;
        } else if (left instanceof String && right instanceof String) {
          return (leftString).compareTo(rightString) < 0;
        }
        throw new RuntimeError(expr.operator, "Operands must be two numbers or two strings.");
      case LESS_EQUAL:
        if (left instanceof Double && right instanceof Double) {
          return Double.compare(leftDouble, rightDouble) <= 0;
        } else if (left instanceof String && right instanceof String) {
          return (leftString).compareTo(rightString) <= 0;
        }
        throw new RuntimeError(expr.operator, "Operands must be two numbers or two strings.");
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

  @Override
  public Object visitExpressionStmt(Expression stmt) {
    return eval(stmt.expression);
  }

  @Override
  public Object visitPrintStmt(Print stmt) {
    Object value = eval(stmt.expression);
    System.out.println(stringify(value));
    return null;
  }

  void interpret(List<Stmt> statements) {
    for (Stmt statement : statements) {
      try {
        lastStatementResult = execute(statement);
      } catch (RuntimeError error) {
        XLox.runtimeError(error);
      }
    }
  }

  Object lastStatementResult() {
    return lastStatementResult;
  }

  private Object eval(Expr expr) {
    return expr.accept(this);
  }

  private Object execute(Stmt statement) {
    return statement.accept(this);
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
