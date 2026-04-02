package com.cuongd.nanosystems.xlox;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.Charset;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.List;

public class XLox {
  private static final Interpreter interpreter = new Interpreter();
  private static boolean hadError = false;
  private static boolean hadRuntimeError = false;

  public static void main(String[] args) throws IOException {
    if (args.length > 1) {
      System.out.println("Usage: jlox [script]");
      System.exit(64);
    } else if (args.length == 1) {
      runFile(args[0]);
    } else {
      runPrompt();
    }
  }

  private static void runFile(String path) throws IOException {
    byte[] bytes = Files.readAllBytes(Paths.get(path));
    run(new String(bytes, Charset.defaultCharset()), false);
    if (hadError) System.exit(65);
    if (hadRuntimeError) System.exit(70);
  }

  private static void runPrompt() throws IOException {
    InputStreamReader input = new InputStreamReader(System.in);
    BufferedReader reader = new BufferedReader(input);

    for (; ; ) {
      System.out.print("> ");
      String line = reader.readLine();
      if (line == null) break;
      run(line, true);
      hadError = false;
      hadRuntimeError = false;
    }
  }

  private static void run(String source, boolean replMode) {
    Scanner scanner = new Scanner(source);
    List<Token> tokens = scanner.scanTokens();
    if (hadError) return; // Syntax error.

    List<Stmt> statements = new Parser(tokens, replMode).parse();
    if (hadError) return; // Parser error.

    interpreter.interpret(statements);
    if (hadRuntimeError) return; // Runtime error.

    if (replMode && interpreter.lastStatementResult() != null) {
      System.out.println(interpreter.lastStatementResult()); // TODO: Impl a Printer.
    }
  }

  static void error(Token token, String message) {
    if (token.type == TokenType.EOF) {
      report(token.line, " at end", message);
    } else {
      report(token.line, " at '" + token.lexeme + "'", message);
    }
  }

  static void error(int line, String message) {
    report(line, "", message);
  }

  private static void report(int line, String where, String message) {
    System.err.println("[line " + line + "] Error" + where + ": " + message);
    hadError = true;
  }

  static void runtimeError(RuntimeError error) {
    System.err.println("[line " + error.token.line + "] Error: " + error.getMessage());
    hadRuntimeError = true;
  }

  // TODO: Rethink this for testing.
  public static boolean inError() {
    return hadError;
  }

  public static void clearError() {
    hadError = false;
  }
}
