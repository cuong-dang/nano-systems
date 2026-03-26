# Build
BUILD_DIR := build
SOURCE_DIR := src
TEST_DIR := test
SOURCES := $(wildcard $(SOURCE_DIR)/com/cuongd/nanosystems/lox/*.java)
TESTS := $(wildcard $(TEST_DIR)/com/cuongd/nanosystems/lox/*.java)
REL_SOURCES := $(SOURCES:$(SOURCE_DIR)/%=%)
CLASSES := $(addprefix $(BUILD_DIR)/, $(REL_SOURCES:.java=.class))
TEST_CLASSES := $(addprefix $(BUILD_DIR)/, $(TESTS:.java=.class))
JAVAC_OPTIONS := -Werror
# Tools
TOOLS_DIR := tools
GJF_JAR := $(TOOLS_DIR)/google-java-format.jar
GJF := java -jar $(GJF_JAR)
JUNIT_JAR := $(TOOLS_DIR)/junit.jar
JUNIT := java -jar $(JUNIT_JAR)

default: $(CLASSES)
	@: # Don't show "Nothing to be done" output.

clean:
	@ rm -rf $(BUILD_DIR)

fmt: $(GJF_JAR)
	@ find . -name "*.java" -print0 | \
	  xargs -0 $(GJF) --replace

fmt-check: $(GJF_JAR)
	@ find . -name "*.java" -print0 | \
	  xargs -0 $(GJF) --dry-run --set-exit-if-changed

test: $(JUNIT_JAR) default $(TEST_CLASSES)
	@ $(JUNIT) execute --class-path "$(BUILD_DIR):$(BUILD_DIR)/$(TEST_DIR)" --scan-class-path

run: fmt default
	@ java -cp $(BUILD_DIR) com.cuongd.nanosystems.lox.Lox

$(GJF_JAR):
	@ mkdir -p $(TOOLS_DIR)
	curl -L -o $@ https://github.com/google/google-java-format/releases/download/v1.35.0/google-java-format-1.35.0-all-deps.jar

$(JUNIT_JAR):
	@ mkdir -p $(TOOLS_DIR)
	curl -L -o $@ https://repo1.maven.org/maven2/org/junit/platform/junit-platform-console-standalone/6.1.0-M1/junit-platform-console-standalone-6.1.0-M1.jar

$(BUILD_DIR)/%.class: $(SOURCE_DIR)/%.java
	@ mkdir -p $(dir $@)
	@ javac -cp $(SOURCE_DIR) -d $(BUILD_DIR) $(JAVAC_OPTIONS) -implicit:none $<
	@ echo javac $< $(JAVAC_OPTIONS)

$(BUILD_DIR)/$(TEST_DIR)/%.class: $(TEST_DIR)/%.java
	@ mkdir -p $(dir $@)
	@ javac -cp "$(SOURCE_DIR):$(JUNIT_JAR)" -d $(BUILD_DIR)/$(TEST_DIR) $(JAVAC_OPTIONS) $<
	@ echo javac $< $(JAVAC_OPTIONS)

.PHONY: default clean fmt fmt-check run
