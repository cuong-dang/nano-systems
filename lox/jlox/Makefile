# Build
BUILD_DIR := build
SOURCE_DIR := src
SOURCES := $(wildcard $(SOURCE_DIR)/com/cuongd/nanosystems/lox/*.java)
CLASSES := $(addprefix $(BUILD_DIR)/, $(SOURCES:.java=.class))
JAVAC_OPTIONS := -Werror
# Format
GJF := java -jar tools/google-java-format-1.35.0-all-deps.jar

default: $(CLASSES)
	@: # Don't show "Nothing to be done" output.

clean:
	@ rm -rf $(BUILD_DIR)

fmt:
	@ find . -name "*.java" -print0 | \
	  xargs -0 $(GJF) --replace

fmt-check:
	@ find . -name "*.java" -print0 | \
	  xargs -0 $(GJF) --dry-run --set-exit-if-changed

$(BUILD_DIR)/%.class: %.java
	@ mkdir -p $(BUILD_DIR)
	@ javac -cp $(SOURCE_DIR) -d $(BUILD_DIR) $(JAVAC_OPTIONS) -implicit:none $<
	@ echo javac $< $(JAVAC_OPTIONS)

.PHONY: default clean fmt fmt-check
