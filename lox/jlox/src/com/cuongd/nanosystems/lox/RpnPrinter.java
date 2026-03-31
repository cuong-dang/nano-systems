package com.cuongd.nanosystems.lox;

import static com.cuongd.nanosystems.lox.TokenType.MINUS;

import com.cuongd.nanosystems.lox.Expr.Comma;

class RpnPrinter implements Expr.Visitor<String> {

  String print(Expr expr) {
    return expr.accept(this);
  }

  @Override
  public String visitBinaryExpr(Expr.Binary expr) {
    return expr.left.accept(this) + " " + expr.right.accept(this) + " " + expr.operator.lexeme;
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
  public String visitUnaryExpr(Expr.Unary expr) {
    String operator = expr.operator.lexeme;

    if (expr.operator.type == MINUS) {
      operator = "~";
    }
    return expr.right.accept(this) + " " + operator;
  }

  public String visitCommaExpr(Comma expr) {
    StringBuilder sb = new StringBuilder();
    for (Expr e : expr.exprs) {
      sb.append(e.accept(this) + ",");
    }
    return sb.toString();
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
}
