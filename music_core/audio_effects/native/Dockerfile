# =============================================================================
# Certified Production — DSP Native Library
# =============================================================================
# Собирает libaudio_effects_native.so + ROCm/ZLUDA + C DSP
# Финальный образ — библиотечный, без запускаемого сервиса.
# Используется как источник артефактов (COPY --from=)
# для Elixir-контейнера (music_core).
# =============================================================================
# Этап 1: ROCm/ZLUDA + C libraries
# =============================================================================
FROM registry.astralinux.ru/library/astra/ubi18:latest AS c-builder

ENV DEBIAN_FRONTEND=noninteractive
ENV ROCM_PATH=/opt/rocm
ENV AMDGPU_TARGETS="gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100"

# ZLUDA — фиксированный commit master (HEAD)
# Получен: curl -s https://api.github.com/repos/vosen/ZLUDA/branches/master
ENV ZLUDA_COMMIT=6e2bd0ad97eca44962ae8908426b71a4d0c51ef4

RUN rm -f /etc/apt/sources.list && \
    echo "deb http://dl.astralinux.ru/astra/stable/orel/repository/ orel main contrib non-free" > /etc/apt/sources.list && \
    echo "deb http://dl.astralinux.ru/astra/stable/orel/repository/ orel-updates main contrib non-free" >> /etc/apt/sources.list && \
    echo "deb http://dl.astralinux.ru/astra/stable/orel/repository/ orel-security main contrib non-free" >> /etc/apt/sources.list

# Пакеты сборки с фиксированными версиями
RUN apt-get update && apt-get install -y \
    build-essential=12.9 \
    clang=1:14.0-55.7~deb11u1 \
    lld=1:14.0-55.7~deb11u1 \
    cmake=3.28.3-1astra1 \
    make=4.3-4.1 \
    curl=7.88.1-10+deb12u8 \
    git=1:2.39.5-0+deb12u2 \
    libelf-dev=0.189-1 \
    libdrm-dev=2.4.114-1 \
    libnuma-dev=2.0.16-1 \
    libudev-dev=252.29-1~deb12u1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app/rocm

RUN git clone --depth 1 --branch rocm-6.3.3 https://github.com/ROCm/ROCT-Thunk-Interface.git && \
    git clone --depth 1 --branch rocm-6.3.3 https://github.com/ROCm/ROCR-Runtime.git && \
    git clone --depth 1 --branch rocm-6.3.3 https://github.com/ROCm/clr.git && \
    git clone --depth 1 --branch rocm-6.3.3 https://github.com/ROCm/rocprofiler-register.git

RUN cd ROCT-Thunk-Interface && mkdir -p build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=${ROCM_PATH} .. && make -j$(nproc) && make install

RUN cd rocprofiler-register && mkdir -p build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=${ROCM_PATH} -DCMAKE_BUILD_TYPE=Release .. && \
    make -j$(nproc) && make install

RUN cd ROCR-Runtime/src && mkdir -p build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=${ROCM_PATH} -DCMAKE_BUILD_TYPE=Release \
          -DIMAGE_SUPPORT=OFF -DBUILD_SHADER_COMPILER=OFF -DENABLE_LD=OFF \
          -DTRAP_HANDLER_SUPPORT=OFF \
          -Drocprofiler-register_DIR=${ROCM_PATH}/lib/cmake/rocprofiler-register .. && \
    make -j$(nproc) && make install

RUN cd clr && mkdir -p build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=${ROCM_PATH} -DCMAKE_BUILD_TYPE=Release \
          -DAMDGPU_TARGETS="${AMDGPU_TARGETS}" .. && \
    make -j$(nproc) && make install

# ZLUDA — фиксированный commit
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
RUN git clone https://github.com/vosen/ZLUDA.git /app/zluda && \
    cd /app/zluda && \
    git checkout ${ZLUDA_COMMIT} && \
    cargo build --release --features rocm

# C DSP library
WORKDIR /app/c_src
COPY ./src/c_src/ .
RUN mkdir -p build && cd build && cmake .. && make -j$(nproc)

# =============================================================================
# Этап 2: Rust .so builder
# =============================================================================
FROM registry.astralinux.ru/library/astra/ubi18:latest AS rust-builder

RUN rm -f /etc/apt/sources.list && \
    echo "deb http://dl.astralinux.ru/astra/stable/orel/repository/ orel main contrib non-free" > /etc/apt/sources.list && \
    echo "deb http://dl.astralinux.ru/astra/stable/orel/repository/ orel-updates main contrib non-free" >> /etc/apt/sources.list && \
    echo "deb http://dl.astralinux.ru/astra/stable/orel/repository/ orel-security main contrib non-free" >> /etc/apt/sources.list

# Пакеты сборки с фиксированными версиями
RUN apt-get update && apt-get install -y \
    build-essential=12.9 \
    cmake=3.28.3-1astra1 \
    make=4.3-4.1 \
    pkg-config=1.8.1-1 \
    curl=7.88.1-10+deb12u8 \
    libsodium-dev=1.0.18-1 \
    libssl-dev=3.0.14-1~deb12u2 \
    libavcodec-dev=7:5.1.6-0+deb12u1 \
    libavformat-dev=7:5.1.6-0+deb12u1 \
    libavutil-dev=7:5.1.6-0+deb12u1 \
    libswresample-dev=7:5.1.6-0+deb12u1 \
    portaudio19-dev=19.6.0-1.2 \
    libasound2-dev=1.2.8-1 \
    libpulse-dev=16.1+dfsg1-2+b1 \
    && rm -rf /var/lib/apt/lists/*

# Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /app
COPY ./Cargo.toml ./Cargo.lock ./
COPY ./src/ ./src/
COPY ./tests/ ./tests/
COPY ./rustler.toml ./

RUN cargo fetch
RUN cargo build --release --features parallel
RUN mkdir -p priv/native && \
    cp target/release/libaudio_effects_native.so priv/native/

# dlopen-тест: проверка, что .so загружается
RUN echo '#include <dlfcn.h>\n#include <stdio.h>\nint main() {\n    void* h = dlopen("/app/priv/native/libaudio_effects_native.so", RTLD_NOW);\n    if (!h) { fprintf(stderr, "dlopen failed: %s\\n", dlerror()); return 1; }\n    printf("✅ libaudio_effects_native.so loaded successfully\\n");\n    dlclose(h);\n    return 0;\n}' > /tmp/test_nif.c && \
    gcc -ldl /tmp/test_nif.c -o /tmp/test_nif && /tmp/test_nif

# =============================================================================
# Этап 3: Runtime — минимальный библиотечный образ
# =============================================================================
FROM registry.astralinux.ru/library/astra/ubi18:latest

LABEL \
  version="1.0.0-rc1" \
  description="DSP Native Library (ROCm + ZLUDA + Rust NIF)" \
  vendor="Elixir Music Bot" \
  rocm-version="6.3.3" \
  zluda-commit="${ZLUDA_COMMIT}" \
  astra-version="1.8.0" \
  build-date="${BUILD_DATE:-unknown}"

ENV DEBIAN_FRONTEND=noninteractive
ENV ROCM_PATH=/opt/rocm
ENV LD_LIBRARY_PATH=/opt/rocm/lib:/opt/zluda
ENV PATH=/opt/rocm/bin:${PATH}
ENV HIP_PLATFORM=amd
ENV ZLUDA_SUPPORT=1

RUN rm -f /etc/apt/sources.list && \
    echo "deb http://dl.astralinux.ru/astra/stable/orel/repository/ orel main contrib non-free" > /etc/apt/sources.list && \
    echo "deb http://dl.astralinux.ru/astra/stable/orel/repository/ orel-updates main contrib non-free" >> /etc/apt/sources.list && \
    echo "deb http://dl.astralinux.ru/astra/stable/orel/repository/ orel-security main contrib non-free" >> /etc/apt/sources.list

# Минимальные рантайм-зависимости (фиксированные версии)
RUN apt-get update && apt-get install -y \
    libcurl4=7.88.1-10+deb12u8 \
    libzstd1=1.5.5+dfsg2-2 \
    libelf1=0.189-1 \
    libdrm2=2.4.114-1 \
    libnuma1=2.0.16-1 \
    libudev1=252.29-1~deb12u1 \
    libavcodec58=7:5.1.6-0+deb12u1 \
    libswresample3=7:5.1.6-0+deb12u1 \
    libpulse0=16.1+dfsg1-2+b1 \
    libasound2=1.2.8-1 \
    libssl3=3.0.14-1~deb12u2 \
    libsodium23=1.0.18-1 \
    ffmpeg=7:5.1.6-0+deb12u1 \
    ca-certificates=20240311 \
    curl=7.88.1-10+deb12u8 \
    && rm -rf /var/lib/apt/lists/*

# ROCm runtime
COPY --from=c-builder /opt/rocm/lib/ /opt/rocm/lib/
COPY --from=c-builder /opt/rocm/bin/ /opt/rocm/bin/

# ZLUDA
COPY --from=c-builder /app/zluda/target/release/ /opt/zluda/

# C DSP library
COPY --from=c-builder /app/c_src/build/libdsp.so /usr/local/lib/
RUN ldconfig

# Rust .so (NIF для Elixir)
COPY --from=rust-builder /app/priv/native/ /app/priv/native/
COPY --from=rust-builder /tmp/test_nif /tmp/test_nif

# Проверка целостности артефактов
RUN /tmp/test_nif && \
    test -f /usr/local/lib/libdsp.so && \
    echo "✅ All DSP artifacts present"

# HEALTHCHECK не требуется — библиотечный образ (без сервера)
HEALTHCHECK NONE

# Без CMD — образ используется как источник артефактов
# (COPY --from= для Elixir-контейнера).
# Если нужен standalone-сервер — используйте c_src/Dockerfile.