BUILD_DIR := build
SOURCE_DIR := src

# Mode configuration.
ifeq ($(MODE),debug)
	CFLAGS += -O0 -DDEBUG -g
	MODE := $(BUILD_DIR)/debug
else
	CFLAGS += -O3 -flto
	MODE := $(BUILD_DIR)/release
endif

# Files.
HEADERS := $(wildcard $(SOURCE_DIR)/*.h)
SOURCES := $(wildcard $(SOURCE_DIR)/*.c)
OBJECTS := $(addprefix $(BUILD_DIR)/$(MODE)/, $(notdir $(SOURCES:.c=.o)))

# C flags.
CFLAGS := -std=c99 -Wall -Wextra -Werror -Wpedantic -Wno-unused-parameter

# Targets ---------------------------------------------------------------------

run: $(BUILD_DIR)/xlox
	@ ./$(BUILD_DIR)/xlox

clean:
	@ rm -rf $(BUILD_DIR)

# Link the interpreter.
$(BUILD_DIR)/xlox: $(OBJECTS)
	$(CC) $(CFLAGS) $^ -o $@

# Compile object files.
$(BUILD_DIR)/$(MODE)/%.o: $(SOURCE_DIR)/%.c $(HEADERS)
	@ mkdir -p $(BUILD_DIR)/$(MODE)
	$(CC) -c $(C_LANG) $(CFLAGS) -o $@ $<

.PHONY: run clean
