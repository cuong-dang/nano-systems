package com.cuongd.nanosystems.xlox;

import static com.cuongd.nanosystems.xlox.TokenType.MINUS;

import com.cuongd.nanosystems.xlox.Expr.Comma;
import com.cuongd.nanosystems.xlox.Expr.Variable;
import com.cuongd.nanosystems.xlox.Stmt.Expression;
import com.cuongd.nanosystems.xlox.Stmt.Print;
import com.cuongd.nanosystems.xlox.Stmt.Var;

class RpnPrinter implements Expr.Visitor<String>, Stmt.Visitor<String> {

  String print(Expr expr) {
    return expr.accept(this);
  }

  String print(Stmt stmt) {
    return stmt.accept(this);
  }

  @Override
  public String visitAssignExpr(Expr.Assign expr) {
    throw new UnsupportedOperationException("Unimplemented method 'visitAssignExpr'");
  }

  @Override
  public String visitBinaryExpr(Expr.Binary expr) {
    return expr.left.accept(this) + " " + expr.right.accept(this) + " " + expr.operator.lexeme;
  }

  @Override
  public String visitCommaExpr(Comma expr) {
    StringBuilder sb = new StringBuilder();
    for (Expr e : expr.exprs) {
      sb.append(e.accept(this) + ",");
    }
    return sb.toString();
  }

  @Override
  public String visitGroupingExpr(Expr.Grouping expr) {
    return expr.expression.accept(this);
  }

  @Override
  public String visitLiteralExpr(Expr.Literal expr) {
    return expr.value.toString();
  }

  @Override
  public String visitTernaryExpr(Expr.Ternary expr) {
    return expr.cond.accept(this)
        + " "
        + expr.yes.accept(this)
        + " "
        + expr.no.accept(this)
        + " ?:";
  }

  @Override
  public String visitUnaryExpr(Expr.Unary expr) {
    String operator = expr.operator.lexeme;

    if (expr.operator.type == MINUS) {
      operator = "~";
    }
    return expr.right.accept(this) + " " + operator;
  }

  @Override
  public String visitVariableExpr(Variable expr) {
    throw new UnsupportedOperationException("Unimplemented method 'visitVariableExpr'");
  }

  @Override
  public String visitExpressionStmt(Expression stmt) {
    return stmt.expression.accept(this);
  }

  @Override
  public String visitPrintStmt(Print stmt) {
    throw new UnsupportedOperationException("Unimplemented method 'visitPrintStmt'");
  }

  @Override
  public String visitVarStmt(Var stmt) {
    throw new UnsupportedOperationException("Unimplemented method 'visitVarStmt'");
  }
}
