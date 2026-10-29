# Makefile для C DSP проекта
# Поддержка: CPU, CUDA, ROCk (AMD GPU), ZLUDA

CC = gcc
CFLAGS = -Wall -Wextra -O2 -std=c++17 -Iinclude -Icommon/include -Igpu/include
LDFLAGS = -lm

# --- Бэкенды ---
CUDA_SUPPORT ?= 0
ROCK_SUPPORT ?= 0
ZLUDA_SUPPORT ?= 0

# --- CUDA ---
NVCC = nvcc
CUDA_FLAGS = -arch=sm_50 --compiler-options -fPIC
CUDA_DIR = cuda
CUDA_SOURCES = $(wildcard $(CUDA_DIR)/*.cu)
CUDA_OBJECTS = $(patsubst $(CUDA_DIR)/%.cu, $(BUILD_DIR)/%.o, $(CUDA_SOURCES))

ifeq ($(CUDA_SUPPORT),1)
    OBJECTS += $(CUDA_OBJECTS)
    LDFLAGS += -lcudart
    CFLAGS += -DCUDA_SUPPORT=1
endif

# --- ROCk (AMD GPU через /dev/kfd) ---
ROCK_DIR = gpu
ROCK_SRC_DIR = $(ROCK_DIR)/src
ROCK_SOURCES = $(wildcard $(ROCK_SRC_DIR)/*.c)
ROCK_OBJECTS = $(patsubst $(ROCK_SRC_DIR)/%.c, $(BUILD_DIR)/%.o, $(ROCK_SOURCES))

ifeq ($(ROCK_SUPPORT),1)
    OBJECTS += $(ROCK_OBJECTS)
    CFLAGS += -DROCK_SUPPORT=1
endif

# --- ZLUDA (CUDA API на AMD GPU) ---
# ZLUDA работает из коробки через LD_PRELOAD, компиляции не требует
ifeq ($(ZLUDA_SUPPORT),1)
    CFLAGS += -DZLUDA_SUPPORT=1
endif

# --- Директории ---
CPU_DIR = cpu
CPU_SRC_DIR = $(CPU_DIR)/src
COMMON_DIR = common
COMMON_SRC_DIR = $(COMMON_DIR)/src
COMMON_INCLUDE_DIR = $(COMMON_DIR)/include
SRC_DIR = src
INCLUDE_DIR = include
GPU_INCLUDE_DIR = $(ROCK_DIR)/include
TEST_DIR = tests
EXAMPLES_DIR = examples
BUILD_DIR = build
LIB_DIR = lib

# --- Файлы ---
SOURCES = $(wildcard $(SRC_DIR)/*.c) $(wildcard $(COMMON_SRC_DIR)/*.c)
OBJECTS = $(patsubst $(SRC_DIR)/%.c, $(BUILD_DIR)/%.o, $(wildcard $(SRC_DIR)/*.c))
OBJECTS += $(patsubst $(COMMON_SRC_DIR)/%.c, $(BUILD_DIR)/%.o, $(wildcard $(COMMON_SRC_DIR)/*.c))
LIBRARY = $(LIB_DIR)/libdsp.a

# --- Тесты ---
TEST_SOURCES = $(wildcard $(TEST_DIR)/*.c)
TEST_DSP_OBJECTS = $(BUILD_DIR)/test_dsp.o
EXTENDED_TEST_OBJECTS = $(BUILD_DIR)/test_extended.o
TEST_EXECUTABLE = $(BUILD_DIR)/test_dsp
EXTENDED_TEST_EXECUTABLE = $(BUILD_DIR)/test_extended

$(shell mkdir -p $(BUILD_DIR) $(LIB_DIR))

# ============================================================================
# Цели сборки
# ============================================================================

all: $(LIBRARY)

$(LIBRARY): $(OBJECTS)
	ar rcs $@ $^

# --- CPU ---
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c
	$(CC) $(CFLAGS) -I$(COMMON_INCLUDE_DIR) -c $< -o $@

$(BUILD_DIR)/%.o: $(CPU_SRC_DIR)/%.c
	$(CC) $(CFLAGS) -I$(COMMON_INCLUDE_DIR) -c $< -o $@

$(BUILD_DIR)/%.o: $(COMMON_SRC_DIR)/%.c
	$(CC) $(CFLAGS) -I$(COMMON_INCLUDE_DIR) -c $< -o $@

# --- CUDA ---
$(BUILD_DIR)/%.o: $(CUDA_DIR)/%.cu
	$(NVCC) $(CUDA_FLAGS) -Iinclude -I$(GPU_INCLUDE_DIR) -Icommon/include -c $< -o $@

# --- ROCk ---
$(BUILD_DIR)/%.o: $(ROCK_SRC_DIR)/%.c
	$(CC) $(CFLAGS) -I$(GPU_INCLUDE_DIR) -c $< -o $@

# ============================================================================
# Примеры
# ============================================================================

EXAMPLE_SOURCES = $(wildcard $(EXAMPLES_DIR)/*.c)
EXAMPLE_OBJECTS = $(patsubst $(EXAMPLES_DIR)/%.c, $(BUILD_DIR)/%.o, $(EXAMPLE_SOURCES))
EXAMPLE_EXECUTABLE = $(BUILD_DIR)/example

example: $(EXAMPLE_EXECUTABLE)
	./$(EXAMPLE_EXECUTABLE)

$(EXAMPLE_EXECUTABLE): $(LIBRARY) $(EXAMPLE_OBJECTS)
	$(CC) $(EXAMPLE_OBJECTS) -L$(LIB_DIR) -ldsp $(LDFLAGS) -o $@

$(BUILD_DIR)/%.o: $(EXAMPLES_DIR)/%.c
	$(CC) $(CFLAGS) -c $< -o $@

# ============================================================================
# Тесты
# ============================================================================

test: $(TEST_EXECUTABLE)
	./$(TEST_EXECUTABLE)

$(TEST_EXECUTABLE): $(LIBRARY) $(TEST_DSP_OBJECTS)
	$(CC) $(TEST_DSP_OBJECTS) -L$(LIB_DIR) -ldsp $(LDFLAGS) -o $@

$(EXTENDED_TEST_EXECUTABLE): $(LIBRARY) $(EXTENDED_TEST_OBJECTS)
	$(CC) $(EXTENDED_TEST_OBJECTS) -L$(LIB_DIR) -ldsp $(LDFLAGS) -o $@

test_extended: $(EXTENDED_TEST_EXECUTABLE)
	./$(EXTENDED_TEST_EXECUTABLE)

$(BUILD_DIR)/%.o: $(TEST_DIR)/%.c
	$(CC) $(CFLAGS) -c $< -o $@

# ============================================================================
# Служебные
# ============================================================================

clean:
	rm -rf $(BUILD_DIR) $(LIB_DIR)

install: $(LIBRARY)
	cp $(LIBRARY) /usr/local/lib/
	cp -r $(INCLUDE_DIR)/* /usr/local/include/
	cp -r $(GPU_INCLUDE_DIR)/* /usr/local/include/

help:
	@echo "Доступные цели:"
	@echo "  all             - Собрать библиотеку"
	@echo "  example         - Собрать и запустить пример"
	@echo "  test            - Базовые тесты"
	@echo "  test_extended   - Расширенные тесты (fuzzing, perf)"
	@echo "  clean           - Очистить сборку"
	@echo "  install         - Установить в /usr/local"
	@echo ""
	@echo "Переменные GPU-бэкендов (CUDA_SUPPORT/ROCK_SUPPORT/ZLUDA_SUPPORT):"
	@echo "  make CUDA_SUPPORT=1          - Собрать с CUDA"
	@echo "  make ROCK_SUPPORT=1          - Собрать с ROCk (AMD GPU)"
	@echo "  make ZLUDA_SUPPORT=1         - Собрать с ZLUDA"
	@echo "  make CUDA_SUPPORT=1 ROCK_SUPPORT=1  - Все GPU-бэкенды"

.PHONY: all example test test_extended clean install help