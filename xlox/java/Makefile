# Sources
BUILD_DIR := build
SOURCE_DIR := src
TEST_DIR := test
PKG_PATH := com/cuongd/nanosystems/xlox

# The following is a hack to make sure we run generate-ast first and
# then re-run make so that SOURCES include the generated classes.
AST_DONE := $(SOURCE_DIR)/$(PKG_PATH)/.ast.done
# Forces make to run generate-ast here before continue.
-include $(AST_DONE)

SOURCES := $(shell find $(SOURCE_DIR) -name "*.java")
TESTS := $(shell find $(TEST_DIR) -name "*.java")
CLASSES := $(addprefix $(BUILD_DIR)/, $(SOURCES:.java=.class))
TEST_CLASSES := $(addprefix $(BUILD_DIR)/, $(TESTS:.java=.class))
JAVAC_OPTIONS := -Werror -implicit:none

# Tools
TOOL_DIR := tool
GJF_JAR := $(TOOL_DIR)/google-java-format.jar
JUNIT_JAR := $(TOOL_DIR)/junit.jar

# Common targets
default: generate-ast $(CLASSES)
	@: # Don't show "Nothing to be done" output.

clean:
	@ rm -rf $(BUILD_DIR)
# AST classes
	@ rm -rf $(SOURCE_DIR)/$(PKG_PATH)/.ast.done
	@ rm -rf $(SOURCE_DIR)/$(PKG_PATH)/Expr.java
	@ rm -rf $(SOURCE_DIR)/$(PKG_PATH)/Stmt.java

fmt: $(GJF_JAR)
	@ find . -name "*.java" -print0 | \
	  xargs -0 java -jar $(GJF_JAR) --replace

test: $(JUNIT_JAR) default $(TEST_CLASSES)
	@ java -jar $(JUNIT_JAR) execute \
	    --class-path "$(BUILD_DIR)/$(SOURCE_DIR):$(BUILD_DIR)/$(TEST_DIR)" \
		--scan-class-path

ARGS ?=
run: default
	@ java -cp $(BUILD_DIR)/$(SOURCE_DIR) com.cuongd.nanosystems.xlox.XLox $(ARGS)

todo:
	@ grep -rn "TODO" . --exclude="Makefile"

# Build src & test
$(BUILD_DIR)/$(SOURCE_DIR)/%.class: $(SOURCE_DIR)/%.java
	@ mkdir -p $(dir $@)
	@ javac -cp $(SOURCE_DIR) -d $(BUILD_DIR)/$(SOURCE_DIR) $(JAVAC_OPTIONS) $<
	@ echo javac $< $(JAVAC_OPTIONS)

$(BUILD_DIR)/$(TEST_DIR)/%.class: $(TEST_DIR)/%.java
	@ mkdir -p $(dir $@)
	@ javac -cp "$(SOURCE_DIR):$(TEST_DIR):$(JUNIT_JAR)" -d $(BUILD_DIR)/$(TEST_DIR) $(JAVAC_OPTIONS) $<
	@ echo javac $< $(JAVAC_OPTIONS)

# Generate AST classes
generate-ast: $(AST_DONE)
	@: # Don't show "Nothing to be done" output.
$(AST_DONE): $(BUILD_DIR)/$(TOOL_DIR)/GenerateAst.class
	@ java -cp $(BUILD_DIR) tool.GenerateAst "$(SOURCE_DIR)/$(PKG_PATH)"
	@ touch $@
$(BUILD_DIR)/tool/GenerateAst.class: $(TOOL_DIR)/GenerateAst.java
	@ javac -d $(BUILD_DIR) $(JAVAC_OPTIONS) $<

# Download tools
$(GJF_JAR):
	curl -L -o $@ https://github.com/google/google-java-format/releases/download/v1.35.0/google-java-format-1.35.0-all-deps.jar

$(JUNIT_JAR):
	curl -L -o $@ https://repo1.maven.org/maven2/org/junit/platform/junit-platform-console-standalone/6.1.0-M1/junit-platform-console-standalone-6.1.0-M1.jar

.PHONY: default clean fmt test run todo generate-ast
