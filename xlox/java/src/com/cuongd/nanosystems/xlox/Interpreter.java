package com.cuongd.nanosystems.xlox;

import static com.cuongd.nanosystems.xlox.TokenType.OR;

import com.cuongd.nanosystems.xlox.Expr.*;
import com.cuongd.nanosystems.xlox.Stmt.*;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

class Interpreter implements Expr.Visitor<Object>, Stmt.Visitor<Object> {
  final Environment globals = new Environment();
  private Environment environment = globals;
  private final Map<Expr, Integer> locals = new HashMap<>();

  private Object lastStatementResult;
  private static final Object uninitialized = new Object();

  Interpreter() {
    globals.define(
        "clock",
        new XLoxCallable() {
          @Override
          public int arity() {
            return 0;
          }

          @Override
          public Object call(Interpreter interpreter, List<Object> arguments) {
            return System.currentTimeMillis() / 1000.0;
          }

          @Override
          public String toString() {
            return "<native fn>";
          }
        });
  }

  @Override
  public Object visitAssignExpr(Assign expr) {
    Object value = eval(expr.value);
    Integer distance = locals.get(expr);
    if (distance != null) {
      environment.assignAt(distance, expr.name, value);
    } else {
      globals.assign(expr.name, value);
    }
    return value;
  }

  @Override
  public Object visitBinaryExpr(Binary expr) {
    Object left = eval(expr.left);
    Object right = eval(expr.right);
    Double leftDouble = left instanceof Double ? (double) left : null;
    Double rightDouble = right instanceof Double ? (double) right : null;
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
  public Object visitCallExpr(Call expr) {
    Object callee = eval(expr.callee);

    if (!(callee instanceof XLoxCallable)) {
      throw new RuntimeError(expr.paren, "Can only call functions and classes.");
    }

    List<Object> arguments = new ArrayList<>();
    for (Expr argument : expr.arguments) {
      arguments.add(eval(argument));
    }

    XLoxCallable function = (XLoxCallable) callee;
    if (arguments.size() != function.arity()) {
      throw new RuntimeError(
          expr.paren,
          "Expected " + function.arity() + " arguments but got " + arguments.size() + ".");
    }

    return function.call(this, arguments);
  }

  @Override
  public Object visitCommaExpr(Comma expr) {
    Object result = null;

    for (Expr e : expr.exprs) {
      result = eval(e);
    }
    return result;
  }

  @Override
  public Object visitGroupingExpr(Grouping expr) {
    return eval(expr.expression);
  }

  @Override
  public Object visitLambdaExpr(Lambda expr) {
    return new XLoxFunction(new Function(null, expr), environment);
  }

  @Override
  public Object visitLiteralExpr(Literal expr) {
    return expr.value;
  }

  @Override
  public Object visitLogicalExpr(Logical expr) {
    Object left = eval(expr.left);
    if (expr.operator.type == OR) {
      if (isTruthy(left)) return left;
    } else {
      if (!isTruthy(left)) return left;
    }
    return eval(expr.right);
  }

  @Override
  public Object visitTernaryExpr(Ternary expr) {
    if (isTruthy(eval(expr.cond))) {
      return eval(expr.yes);
    }
    return eval(expr.no);
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
  public Object visitVariableExpr(Variable expr) {
    Object value = lookUpVariable(expr.name, expr);
    if (value == uninitialized) {
      throw new RuntimeError(expr.name, "Variable must be initialized before use.");
    }
    return value;
  }

  @Override
  public Object visitExpressionStmt(Expression stmt) {
    return eval(stmt.expression);
  }

  @Override
  public Object visitFunctionStmt(Function stmt) {
    XLoxFunction function = new XLoxFunction(stmt, environment);
    environment.define(stmt.name.lexeme, function);
    return null;
  }

  @Override
  public Object visitBlockStmt(Block stmt) {
    executeBlock(stmt.statements, new Environment(environment));
    return null;
  }

  @Override
  public Object visitBreakStmt(Break stmt) {
    throw new BreakSignal();
  }

  @Override
  public Object visitIfStmt(If stmt) {
    if (isTruthy(eval(stmt.condition))) {
      execute(stmt.thenBranch);
    } else if (stmt.elseBranch != null) {
      execute(stmt.elseBranch);
    }
    return null;
  }

  @Override
  public Object visitPrintStmt(Print stmt) {
    Object value = eval(stmt.expression);
    System.out.println(stringify(value));
    return null;
  }

  @Override
  public Object visitReturnStmt(Stmt.Return stmt) {
    Object value = null;
    if (stmt.value != null) value = eval(stmt.value);
    throw new Return(value);
  }

  @Override
  public Object visitVarStmt(Var stmt) {
    Object value = uninitialized;
    if (stmt.initializer != null) {
      value = eval(stmt.initializer);
    }
    environment.define(stmt.name.lexeme, value);
    return null;
  }

  @Override
  public Object visitWhileStmt(While stmt) {
    while (isTruthy((eval(stmt.condition)))) {
      try {
        execute(stmt.body);
      } catch (BreakSignal _) {
        return null;
      }
    }
    return null;
  }

  void interpret(List<Stmt> statements) {
    for (Stmt statement : statements) {
      try {
        lastStatementResult = execute(statement);
      } catch (RuntimeError error) {
        XLox.runtimeError(error);
        return;
      }
    }
  }

  private Object eval(Expr expr) {
    return expr.accept(this);
  }

  private Object execute(Stmt statement) {
    return statement.accept(this);
  }

  void executeBlock(List<Stmt> statements, Environment environment) {
    Environment previous = this.environment;
    try {
      this.environment = environment;

      for (Stmt statement : statements) {
        execute(statement);
      }
    } finally {
      this.environment = previous;
    }
  }

  void resolve(Expr expr, int depth) {
    locals.put(expr, depth);
  }

  private Object lookUpVariable(Token name, Expr expr) {
    Integer distance = locals.get(expr);
    if (distance != null) {
      return environment.getAt(distance, name.lexeme);
    } else {
      return globals.get(name);
    }
  }

  private void checkNumberOperand(Token operator, Object operand) {
    if (operand instanceof Double) return;
    throw new RuntimeError(operator, "Operand must be a number.");
  }

  private void checkNumberOperand(Token operator, Object left, Object right) {
    if (left instanceof Double && right instanceof Double) return;
    throw new RuntimeError(operator, "Operands must be numbers.");
  }

  Object lastStatementResult() {
    return lastStatementResult;
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
