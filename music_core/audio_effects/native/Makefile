# Makefile для WSL Ubuntu
# Поддерживает CPU, CUDA, ROCm (ROCk), ZLUDA

CARGO = cargo
PROFILE ?= release
OUT_DIR = target/$(PROFILE)
LIB_NAME = libaudio_effects_native.so
LIB_PATH = $(OUT_DIR)/$(LIB_NAME)

# GPU detection
CUDA_AVAILABLE := $(shell command -v nvcc 2> /dev/null)
ROCM_AVAILABLE := $(shell test -e /dev/kfd && echo 1 || echo 0)
ZLUDA_AVAILABLE := $(shell test -f /opt/zluda/lib/libcuda.so && echo 1 || echo 0)

.PHONY: all

all: detect install build start

start:
	cargo run --release

build:
ifeq ($(CUDA_AVAILABLE),)
ifeq ($(ROCM_AVAILABLE),1)
	$(MAKE) build-rock
else ifeq ($(ZLUDA_AVAILABLE),1)
	$(MAKE) build-zluda
else
	$(MAKE) build-cpu
endif
else
	$(MAKE) build-cuda
endif

# Только CPU
build-cpu:
	RUSTFLAGS="-C target-cpu=native -C opt-level=3 -C codegen-units=1 -C lto=fat -C panic=abort" \
		cargo build --release --features parallel

# CUDA-бэкенд
build-cuda:
	@echo "Building with CUDA backend..."
	nvcc -O3 -ptx -o target/kernels_cuda.ptx src/c_src/gpu/src/dsp_cuda.cu
	RUSTFLAGS="-C target-cpu=native -C opt-level=3 -C codegen-units=1 -C lto=fat -C panic=abort" \
		cargo build --release --features "parallel,gpu-cuda"

# ROCm через ROCk (без HIP)
build-rock:
	@echo "Building with ROCk backend (AMD GPU)..."
	gcc -O3 -march=native -fPIC -shared \
		-I src/c_src/gpu/include \
		-I src/c_src/common/include \
		-o target/libdsp_rock.so \
		src/c_src/gpu/src/dsp_rock.c
	RUSTFLAGS="-C target-cpu=native -C opt-level=3 -C codegen-units=1 -C lto=fat -C panic=abort" \
		cargo build --release --features "parallel,gpu-rock"

# ZLUDA (CUDA API на AMD GPU)
build-zluda:
	@echo "Building with ZLUDA backend..."
	export LD_LIBRARY_PATH=/opt/zluda/lib:$$LD_LIBRARY_PATH
	nvcc -O3 -ptx -o target/kernels_cuda.ptx src/c_src/cuda/dsp_cuda.cu
	RUSTFLAGS="-C target-cpu=native -C opt-level=3 -C codegen-units=1 -C lto=fat -C panic=abort" \
		cargo build --release --features "parallel,gpu-zluda"

build-avx:
	RUSTFLAGS="-C target-cpu=native -C target-feature=+avx2,+fma -C opt-level=3 -C codegen-units=1 -C lto=fat -C panic=abort" \
		cargo build --release --features parallel

build-sse:
	RUSTFLAGS="-C target-cpu=native -C target-feature=+sse4.2 -C opt-level=3 -C codegen-units=1 -C lto=fat -C panic=abort" \
		cargo build --release --features parallel

release:
	RUSTFLAGS="-C target-cpu=native -C opt-level=3 -C codegen-units=1 -C lto=fat -C panic=abort" \
		cargo build --release --features parallel

dev:
	cargo build --features parallel

clean:
	cargo clean
	rm -rf ../priv/native
	rm -f target/kernels_cuda.ptx target/libdsp_rock.so

install: build
	mkdir -p ../priv/native
	cp "$(LIB_PATH)" ../priv/native/
	@if [ -f target/kernels_cuda.ptx ]; then cp target/kernels_cuda.ptx ../priv/native/; fi
	@if [ -f target/libdsp_rock.so ]; then cp target/libdsp_rock.so ../priv/native/; fi

test:
	cargo test --features parallel

bench:
	cargo bench --features "parallel,benchmarks"

lint:
	cargo clippy --features parallel -- -D warnings

fmt:
	cargo fmt

doc:
	cargo doc --features parallel --no-deps --open

# Показать, какой бэкенд будет использован
detect:
	@echo "CUDA available: $(if $(CUDA_AVAILABLE),YES,NO)"
	@echo "ROCm (/dev/kfd): $(if $(ROCM_AVAILABLE:1=YES),NO,YES)"
	@echo "ZLUDA available: $(if $(ZLUDA_AVAILABLE:1=YES),NO,YES)"

help:
	@echo "Available targets:"
	@echo "  detect      - Show available GPU backends"
	@echo "  install     - Build and copy to priv/native"
	@echo "  build       - Auto-detect GPU and build with best backend"
	@echo "  build-cpu   - CPU only (Rust + C fallback)"
	@echo "  build-cuda  - NVIDIA CUDA backend"
	@echo "  build-rock  - AMD ROCk backend (/dev/kfd)"
	@echo "  build-zluda - ZLUDA backend (CUDA on AMD)"
	@echo "  build-avx   - CPU with AVX2+FMA"
	@echo "  build-sse   - CPU with SSE4.2"
	@echo "  dev         - Debug build"
	@echo "  start       - Run in release mode"
	@echo "  clean       - Clean all"
	@echo "  test        - Run tests"
	@echo "  bench       - Benchmarks"
	@echo "  lint        - Clippy"
	@echo "  fmt         - Format"
	@echo "  doc         - Docs"