ifeq ($(CPP),true)
	# Ideally, we'd add -pedantic-errors, but the use of designated initializers
	# means clox relies on some GCC/Clang extensions to compile as C++.
	CFLAGS := -std=c++11
	C_LANG := -x c++
else
	CFLAGS := -std=c99
endif

CFLAGS += -Wall -Wextra -Werror -Wno-unused-parameter

BASE := build
# Mode configuration.
ifeq ($(MODE),debug)
	CFLAGS += -O0 -DDEBUG -g
	BUILD_DIR := $(BASE)/debug
else
	CFLAGS += -O3 -flto
	BUILD_DIR := $(BASE)/release
endif

# Files.
SOURCE_DIR := src
HEADERS := $(wildcard $(SOURCE_DIR)/*.h)
SOURCES := $(wildcard $(SOURCE_DIR)/*.c)
OBJECTS := $(addprefix $(BUILD_DIR)/, $(notdir $(SOURCES:.c=.o)))


# Targets ---------------------------------------------------------------------

run: $(BASE)/xlox
	@ ./$(BASE)/xlox

clean:
	@ rm -rf $(BASE)

# Link the interpreter.
$(BASE)/xlox: $(OBJECTS)
	@ printf "%8s %-40s %s\n" $(CC) $@ "$(CFLAGS)"
	@ mkdir -p $(BASE)
	@ $(CC) $(CFLAGS) $^ -o $@

# Compile object files.
$(BUILD_DIR)/%.o: $(SOURCE_DIR)/%.c $(HEADERS)
	@ printf "%8s %-40s %s\n" $(CC) $< "$(CFLAGS)"
	@ mkdir -p $(BUILD_DIR)
	@ $(CC) -c $(C_LANG) $(CFLAGS) -o $@ $<



.PHONY: run clean
