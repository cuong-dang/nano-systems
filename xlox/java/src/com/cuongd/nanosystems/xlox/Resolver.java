package com.cuongd.nanosystems.xlox;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Stack;

class Resolver implements Expr.Visitor<Void>, Stmt.Visitor<Void> {
  private enum FunctionType {
    NONE,
    FUNCTION,
    METHOD,
  }

  private enum VariableState {
    DECLARED,
    DEFINED,
    READ,
  }

  private static class VariableTokenState {
    final Token name;
    final VariableState state;

    VariableTokenState(Token name, VariableState state) {
      this.name = name;
      this.state = state;
    }
  }

  private final Interpreter interpreter;
  private final Stack<Map<String, VariableTokenState>> scopes = new Stack<>();
  private FunctionType currentFunction = FunctionType.NONE;

  Resolver(Interpreter interpreter) {
    this.interpreter = interpreter;
  }

  @Override
  public Void visitAssignExpr(Expr.Assign expr) {
    resolve(expr.value);
    resolveLocal(expr, expr.name, false);
    return null;
  }

  @Override
  public Void visitBinaryExpr(Expr.Binary expr) {
    resolve(expr.left);
    resolve(expr.right);
    return null;
  }

  @Override
  public Void visitCallExpr(Expr.Call expr) {
    resolve(expr.callee);
    for (Expr argument : expr.arguments) resolve(argument);
    return null;
  }

  @Override
  public Void visitCommaExpr(Expr.Comma expr) {
    for (Expr expression : expr.exprs) resolve(expression);
    return null;
  }

  @Override
  public Void visitGetExpr(Expr.Get expr) {
    resolve(expr.object);
    return null;
  }

  @Override
  public Void visitGroupingExpr(Expr.Grouping expr) {
    resolve(expr.expression);
    return null;
  }

  @Override
  public Void visitLambdaExpr(Expr.Lambda expr) {
    resolveLambda(expr, FunctionType.FUNCTION);
    return null;
  }

  @Override
  public Void visitLiteralExpr(Expr.Literal expr) {
    return null;
  }

  @Override
  public Void visitLogicalExpr(Expr.Logical expr) {
    resolve(expr.left);
    resolve(expr.right);
    return null;
  }

  @Override
  public Void visitSetExpr(Expr.Set expr) {
    resolve(expr.value);
    resolve(expr.object);
    return null;
  }

  @Override
  public Void visitTernaryExpr(Expr.Ternary expr) {
    resolve(expr.cond);
    resolve(expr.yes);
    resolve(expr.no);
    return null;
  }

  @Override
  public Void visitThisExpr(Expr.This expr) {
    resolveLocal(expr, expr.keyword, true);
    return null;
  }

  @Override
  public Void visitUnaryExpr(Expr.Unary expr) {
    resolve(expr.right);
    return null;
  }

  @Override
  public Void visitVariableExpr(Expr.Variable expr) {
    if (!scopes.isEmpty()
        && scopes.peek().get(expr.name.lexeme) != null
        && scopes.peek().get(expr.name.lexeme).state == VariableState.DECLARED) {
      XLox.error(expr.name, "Can't read local variable in its own initializer.");
    }

    resolveLocal(expr, expr.name, true);
    return null;
  }

  @Override
  public Void visitBlockStmt(Stmt.Block stmt) {
    beginScope();
    resolve(stmt.statements);
    endScope();
    return null;
  }

  @Override
  public Void visitBreakStmt(Stmt.Break stmt) {
    return null;
  }

  @Override
  public Void visitClassStmt(Stmt.Class stmt) {
    declare(stmt.name);
    define(stmt.name);

    beginScope();
    scopes.peek().put("this", new VariableTokenState(null, VariableState.READ));

    for (Stmt.Function method : stmt.methods) {
      FunctionType declaration = FunctionType.METHOD;
      resolveLambda(method.lambda, declaration);
    }

    endScope();

    return null;
  }

  @Override
  public Void visitExpressionStmt(Stmt.Expression stmt) {
    resolve(stmt.expression);
    return null;
  }

  @Override
  public Void visitFunctionStmt(Stmt.Function stmt) {
    declare(stmt.name);
    define(stmt.name);

    resolveLambda(stmt.lambda, FunctionType.FUNCTION);
    return null;
  }

  @Override
  public Void visitIfStmt(Stmt.If stmt) {
    resolve(stmt.condition);
    resolve(stmt.thenBranch);
    if (stmt.elseBranch != null) resolve(stmt.elseBranch);
    return null;
  }

  @Override
  public Void visitPrintStmt(Stmt.Print stmt) {
    resolve(stmt.expression);
    return null;
  }

  @Override
  public Void visitReturnStmt(Stmt.Return stmt) {
    if (currentFunction == FunctionType.NONE) {
      XLox.error(stmt.keyword, "Can't return from top-level code.");
    }

    if (stmt.value != null) resolve(stmt.value);
    return null;
  }

  @Override
  public Void visitVarStmt(Stmt.Var stmt) {
    declare(stmt.name);
    if (stmt.initializer != null) {
      resolve(stmt.initializer);
    }
    define(stmt.name);
    return null;
  }

  @Override
  public Void visitWhileStmt(Stmt.While stmt) {
    resolve(stmt.condition);
    resolve(stmt.body);
    return null;
  }

  void resolve(List<Stmt> statements) {
    for (Stmt statement : statements) {
      resolve(statement);
    }
  }

  private void resolve(Stmt stmt) {
    stmt.accept(this);
  }

  private void resolve(Expr expr) {
    expr.accept(this);
  }

  private void beginScope() {
    scopes.push(new HashMap<>());
  }

  private void endScope() {
    for (VariableTokenState ts : scopes.peek().values()) {
      if (!(ts.state == VariableState.READ)) {
        XLox.error(ts.name, "Local variable declared but not read.");
      }
    }
    scopes.pop();
  }

  private void declare(Token name) {
    if (scopes.isEmpty()) return;

    Map<String, VariableTokenState> scope = scopes.peek();
    if (scope.containsKey(name.lexeme)) {
      XLox.error(name, "Already a variable with this name in this scope.");
    }
    scope.put(name.lexeme, new VariableTokenState(name, VariableState.DECLARED));
  }

  private void define(Token name) {
    if (scopes.isEmpty()) return;
    scopes.peek().put(name.lexeme, new VariableTokenState(name, VariableState.DEFINED));
  }

  private void resolveLocal(Expr expr, Token name, boolean markRead) {
    for (int i = scopes.size() - 1; i >= 0; i--) {
      if (scopes.get(i).containsKey(name.lexeme)) {
        interpreter.resolve(expr, scopes.size() - 1 - i);
        if (markRead)
          scopes.get(i).put(name.lexeme, new VariableTokenState(name, VariableState.READ));
        return;
      }
    }
  }

  private void resolveLambda(Expr.Lambda lambda, FunctionType type) {
    FunctionType enclosingFunction = currentFunction;
    currentFunction = type;

    beginScope();
    for (Token param : lambda.params) {
      declare(param);
      define(param);
    }
    resolve(lambda.body);
    endScope();
    currentFunction = enclosingFunction;
  }
}
