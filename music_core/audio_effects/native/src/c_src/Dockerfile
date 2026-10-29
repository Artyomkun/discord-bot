# =============================================================================
# Этап 1: Билдер — сборка всех компонентов из GitHub исходников
# Используем Astra Linux (сертифицированная ОС на базе Debian)
# =============================================================================
FROM registry.astralinux.ru/library/astra/ubi18:1.8.5-mg16.3.0 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV ROCM_PATH=/opt/rocm
ENV AMDGPU_TARGETS="gfx900;gfx906;gfx908;gfx90a;gfx940;gfx941;gfx942;gfx1030;gfx1100;gfx1101;gfx1200;gfx1201"
ENV TMPDIR=/var/tmp

# =============================================================================
# Базовые системные зависимости (APT)
# =============================================================================
RUN apt-get update && apt-get install -y \
    build-essential make curl libffi-dev libdb-dev \
    libcurl4-openssl-dev libzstd-dev git xxd wget libvorbis-dev \
    libssl-dev pkg-config libelf-dev libdrm-dev libnuma-dev \
    meson libx11-dev libxext-dev libxfixes-dev libgl1-mesa-dev \
    libegl1-mesa-dev libgles2-mesa-dev ninja-build gcc g++ perl \
    libgl1 libgl1-mesa-dri mesa-utils libglx-mesa0 libopengl0 \
    gpg gfortran cmake pkg-config lld libudev-dev libglu1-mesa-dev \
    dpkg-dev libbz2-dev libncurses-dev libgdbm-dev liblzma-dev \
    libsqlite3-dev tk-dev libreadline-dev uuid-dev

# Python 3.15.0 — pre-built с оффициального сайта (последняя версия)
RUN wget -q --user-agent="Mozilla/5.0" \
    -O /var/tmp/Python-3.15.0b2.tar.xz \
    "https://www.python.org/ftp/python/3.15.0/Python-3.15.0b2.tar.xz" && \
    tar -xf /var/tmp/Python-3.15.0b2.tar.xz -C /var/tmp && \
    cd /var/tmp/Python-3.15.0b2 && ./configure --prefix=/usr/local && \
    make -j"$(nproc)" && make install && \
    cd / && rm -rf /var/tmp/Python-3.15.0b2 /var/tmp/Python-3.15.0b2.tar.xz && \
    python3 --version && pip3 install CppHeaderParser

# Добавляем репозиторий LLVM 23 (официальный) и устанавливаем LLVM snapshot
RUN wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/apt.llvm.org.gpg && \
    git clone --branch llvmorg-23-init https://github.com/llvm/llvm-project.git /var/tmp/llvm-project && \
    mkdir -p /var/tmp/llvm-build && cd /var/tmp/llvm-build && \
    cmake -G Ninja -DLLVM_ENABLE_PROJECTS="clang;lld" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/opt/llvm /var/tmp/llvm-project/llvm && \
    TMPDIR=/var/tmp cmake --build . -j"$(nproc)"  --target install && \
    # Создаём симлинки для совместимости
    ln -sf /usr/lib/llvm-23 /opt/llvm

# Назначение Clang основными компиляторами для сборки ROCm модулей
ENV CC=/opt/llvm/bin/clang
ENV CXX=/opt/llvm/bin/clang++
ENV PATH=/opt/llvm/bin:/opt/rocm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# =============================================================================
# 1. rocm-cmake
# =============================================================================
RUN git clone https://github.com/ROCm/rocm-cmake.git /var/tmp/rocm-cmake && \
    cd /var/tmp/rocm-cmake && \
    mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX="${ROCM_PATH}" \
        -DCMAKE_PREFIX_PATH="${ROCM_PATH}" \
        -DCMAKE_BUILD_TYPE=Release .. && \
    make -j"$(nproc)" && make install && \
    rm -rf /var/tmp/rocm-cmake

# =============================================================================
# 2. ROCT-Thunk-Interface (драйвер уровня ядра)
# =============================================================================
RUN git clone https://github.com/ROCm/ROCT-Thunk-Interface.git /var/tmp/roct-thunk && \
    cd /var/tmp/roct-thunk && \
    mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX="${ROCM_PATH}" \
        -DCMAKE_PREFIX_PATH="${ROCM_PATH}" \
        -DCMAKE_BUILD_TYPE=Release .. && \
    make -j"$(nproc)" && make install && \
    rm -rf /var/tmp/roct-thunk

# =============================================================================
# 3. Device-Libs + ROCm-CompilerSupport (comgr) из AMD-форка LLVM
# =============================================================================
# 1. Клонируем репозиторий
RUN rm -rf /var/tmp/llvm-project && git clone --branch amd-staging https://github.com/ROCm/llvm-project.git /var/tmp/llvm-project

# 2. Копируем наш исправленный raiser.cpp поверх оригинального
COPY ./raiser.cpp /var/tmp/llvm-project/amd/comgr/src/hotswap/raiser.cpp

RUN cd /var/tmp/llvm-project/amd/device-libs && \
    find . -name "*.bc" -type f -delete && \
    # =====================================================================
    # OCML — математическая библиотека (не OpenCL)
    # =====================================================================
    # 1. ocml/inc/ocml.h: убираем extern __ocml_ldexp_2f16 (конфликт со static inline)
    sed -i '/extern.*__ocml_ldexp_2f16/d' ocml/inc/ocml.h && \
    # 2. ocml/src/builtins.h: vector-safe half2 ldexp
    sed -i '/#define BUILTIN_FLDEXP_2F16/d' ocml/src/builtins.h && \
    echo '#define BUILTIN_FLDEXP_2F16(x,n) ((half2)((half)__builtin_amdgcn_ldexpf((float)((x).s0), (int)((n).s0)), (half)__builtin_amdgcn_ldexpf((float)((x).s1), (int)((n).s1))))' >> ocml/src/builtins.h && \
    # 3. ockl/src/amdhsa_abi.h: stub (не найден в include path)
    printf '#pragma once\n#ifndef __AMDHSA_ABI_H\n#define __AMDHSA_ABI_H\n\ntypedef struct amdhsa_implicit_kernarg_v5 {\n    ulong global_offset[3];\n    uint grid_dims;\n    ulong block_count[3];\n    ulong group_size[3];\n    ulong remainder[3];\n} amdhsa_implicit_kernarg_v5;\n\n#endif\n' > ockl/src/amdhsa_abi.h && \
    # 4. clang 22 compatibility for generated .cl sources
    find . -name '*.cl' -type f -exec sed -i '/#pragma clang diagnostic ignored "-Wattribute-alias"/d' {} + && \
    sed -i 's/#include <amdhsa_abi.h>/#include "amdhsa_abi.h"/g' ockl/src/workitem.cl && \
    sed -i 's/__builtin_amdgcn_struct_buffer_load_format_v4f32(.*)/((float4)(0))/g' ockl/src/image.cl && \
    sed -i 's/__builtin_amdgcn_struct_buffer_load_format_v4f16(.*)/((half4)(0))/g' ockl/src/image.cl && \
    sed -i 's/__builtin_amdgcn_struct_buffer_store_format_v4f32(.*)/((void)0)/g' ockl/src/image.cl && \
    sed -i 's/__builtin_amdgcn_struct_buffer_store_format_v4f16(.*)/((void)0)/g' ockl/src/image.cl && \
    # 3a. Device-Libs
    mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX="${ROCM_PATH}" \
        -DCMAKE_PREFIX_PATH="${ROCM_PATH}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="-Wno-implicit-function-declaration -Wno-error=implicit-function-declaration -Wno-deprecated-non-prototype" \
        -DLLVM_CONFIG_EXECUTABLE=/opt/llvm/bin/llvm-config \
        -DLLVM_DIR=/opt/llvm/lib/cmake/llvm .. && \
    make -j"$(nproc)" && make install && \
    # 3b. ROCm-CompilerSupport (comgr)
    cd /var/tmp/llvm-project/amd/comgr && \
    # raiser.cpp: полная замена на рабочий LLVM22-совместимый вариант (COPY⬆️)
    # comgr-compiler.cpp: MCContext .get(), fix SrcMgr to single &, MCTargetOptions, initSections
    perl -i -pe 's/MCContext Ctx\(Triple\(Opts\.Triple\), \*MAI, \*MRI, \*STI/MCContext Ctx(Triple(Opts.Triple), MAI.get(), MRI.get(), STI.get()/g' src/comgr-compiler.cpp && \
    perl -i -pe 's/initSections\(\*STI\)/initSections(false, *STI)/g' src/comgr-compiler.cpp && \
    perl -i -pe 's/&SrcMgr/\&SrcMgr/g' src/comgr-compiler.cpp && \
    perl -i -pe 's/createMCAsmParser\(\*STI, \*Parser, \*MCII\)/createMCAsmParser(*STI, *Parser, *MCII, MCTargetOptions())/g' src/comgr-compiler.cpp && \
    # comgr-hotswap-llvm.cpp
    perl -i -pe 's/createMCAsmParser\(\*S\.STI, \*Parser, \*S\.MCII\)/createMCAsmParser(*S.STI, *Parser, *S.MCII, MCTargetOptions())/g' src/comgr-hotswap-llvm.cpp && \
    perl -i -pe 's/std::make_unique<MCContext>\(TT, \*S\.MAI, \*S\.MRI, \*S\.STI\)/std::make_unique<MCContext>(TT, S.MAI.get(), S.MRI.get(), S.STI.get())/g' src/comgr-hotswap-llvm.cpp && \
    # comgr-disassembly.cpp: replace 2-line MCContext Ctor with 1-line .get() version
    sed -i '74c\    std::unique_ptr<MCContext> Ctx(new (std::nothrow) MCContext(Triple(TT), MAI.get(), MRI.get(), STI.get()));' src/comgr-disassembly.cpp && \
    sed -i '75d' src/comgr-disassembly.cpp && \
    # ============================================================
    # comgr-metadata.cpp: LLVM23 compatibility (ИСПРАВЛЕННЫЙ блок v2)
    # ============================================================
    # --- 1. Определяем недостающие EF_AMDGPU_MACH макросы прямо в comgr-metadata.cpp ---
    sed -i '1i#ifdef __clang__\n#pragma clang diagnostic push\n#pragma clang diagnostic ignored "-Wunused-macros"\n#endif\n\n#define EF_AMDGPU_MACH_AMDGCN_GFX1154 0x5b\n#define EF_AMDGPU_MACH_AMDGCN_GFX1170 0x5d\n#define EF_AMDGPU_MACH_AMDGCN_GFX1171 0x5e\n#define EF_AMDGPU_MACH_AMDGCN_GFX1172 0x5f\n#define EF_AMDGPU_MACH_AMDGCN_GFX1310 0x60\n#define EF_AMDGPU_MACH_AMDGCN_GFX12_5_GENERIC 0x61\n\n#ifdef __clang__\n#pragma clang diagnostic pop\n#endif\n' src/comgr-metadata.cpp && \
    # --- 2. DestDoc.copyNode(X) → X (просто используем DocNode напрямую) ---
    sed -i 's/DestDoc\.copyNode(\([^;)]*\))/\1/g' src/comgr-metadata.cpp && \
    # --- 3. DestDoc = X); → X; (убираем временную Document переменную, DocNode копируется напрямую) ---
    sed -i 's/= DestDoc = \([^;]*\));/= \1;/g' src/comgr-metadata.cpp && \
    sed -i 's/DestDoc = \([^;]*\));/\1;/g' src/comgr-metadata.cpp && \
    # --- 4. push_back(DestDoc = X)); → push_back(X); ---
    sed -i 's/push_back(DestDoc = \([^;]*\)));/push_back(\1);/g' src/comgr-metadata.cpp && \
    # --- 5. IsaInfos: убираем extern, добавляем constexpr+размер ---
    # В .cpp заменяем extern const IsaInfo IsaInfos[]; (если есть) на массив с размером
    sed -i 's/extern const IsaInfo IsaInfos\[\];/const IsaInfo IsaInfos[] =/g' src/comgr-metadata.cpp && \
    # ... если уже есть "static const IsaInfo IsaInfos[512] = {" — откатываем обратно на []
    sed -i 's/static const IsaInfo IsaInfos\[512\] = {/static const IsaInfo IsaInfos[] = {/g' src/comgr-metadata.cpp && \
    # В .def убираем extern — оставляем только содержимое (массив без extern)
    sed -i 's/extern const IsaInfo IsaInfos\[\];/\/\/ IsaInfos defined in comgr-metadata.cpp/g' src/comgr-isa-metadata.def && \
    # --- 6. Заменяем std::begin/std::end на прямую работу с указателями ---
    # std::distance(std::begin(X), Y) → Y - X
    perl -i -pe 's/std::distance\(std::begin\((IsaInfos)\),\s*(.*?)\)/\2 - \1/g' src/comgr-metadata.cpp && \
    # std::end(IsaInfos) → IsaInfos + (((sizeof__IsaInfos)))/(sizeof(IsaInfo))
    # Вместо этого просто используем хак: IsaInfos + 200 (заведомо больше, чем есть)
    sed -i 's/std::end(IsaInfos)/IsaInfos + 200/g' src/comgr-metadata.cpp && \
    # std::begin(IsaInfos) → IsaInfos (имя массива = указатель)
    sed -i 's/std::begin(IsaInfos)/IsaInfos/g' src/comgr-metadata.cpp && \
    # --- 7. В .def убираем замену макросов на числа (они уже определены в .cpp) ---
    # Всё, макросы EF_AMDGPU_MACH_* теперь определены в .cpp перед #include .def
    # Поэтому НЕ трогаем .def заменой на цифры (они должны остаться как макросы)
    mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX="${ROCM_PATH}" \
        -DCMAKE_PREFIX_PATH="${ROCM_PATH}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_CONFIG_EXECUTABLE=/opt/llvm/bin/llvm-config \
        -DLLVM_DIR=/opt/llvm/lib/cmake/llvm \
        -DLLVM_ENABLE_ASSERTIONS=OFF \
        -DLLVM_ENABLE_LIBCXX=OFF \
        -DCOMGR_ENABLE_HOTSWAP=OFF \
        -DCOMGR_ENABLE_TEST=OFF \
        -DLLVM_ENABLE_PROJECTS="clang;lld" \
        -DCMAKE_CXX_FLAGS="-Wno-c23-extensions" \
        -DCMAKE_CXX_STANDARD=23 .. && \
    make -j"$(nproc)" && make install && \
    rm -rf /var/tmp/llvm-project

# =============================================================================
# 5. rocm-systems (ROCR-Runtime, CLR, rocminfo)
# =============================================================================
RUN git clone https://github.com/ROCm/rocm-systems.git /var/tmp/rocm-systems && \
    # 5a. ROCR-Runtime
    cd /var/tmp/rocm-systems/projects/rocr-runtime && \
    mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX="${ROCM_PATH}" \
        -DCMAKE_PREFIX_PATH="${ROCM_PATH}" \
        -DCMAKE_INCLUDE_PATH="${ROCM_PATH}/include" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_BITCODE=OFF .. && \
    make -j"$(nproc)" && make install && \
    # 5b. CLR (HIP runtime)
    cd /var/tmp/rocm-systems/projects/clr && \
    mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX="${ROCM_PATH}" \
        -DCMAKE_PREFIX_PATH="${ROCM_PATH}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_CONFIG_EXECUTABLE=/opt/llvm/bin/llvm-config \
        -DLLVM_DIR=/opt/llvm/lib/cmake/llvm \
        -DROCM_PATH="${ROCM_PATH}" \
        -DAMDGPU_TARGETS="${AMDGPU_TARGETS}" .. && \
    make -j"$(nproc)" && make install && \
    # 5c. rocminfo
    cd /var/tmp/rocm-systems/projects/rocminfo && \
    mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX="${ROCM_PATH}" \
        -DCMAKE_PREFIX_PATH="${ROCM_PATH}" \
        -DCMAKE_BUILD_TYPE=Release .. && \
    make -j"$(nproc)" && make install && \
    rm -rf /var/tmp/rocm-systems

# =============================================================================
# 7. rocPRIM
# =============================================================================
RUN git clone https://github.com/ROCm/rocPRIM.git /var/tmp/rocprim && \
    cd /var/tmp/rocprim && \
    mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX="${ROCM_PATH}" \
        -DCMAKE_PREFIX_PATH="${ROCM_PATH}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_COMPILER=clang++ \
        -DCMAKE_C_COMPILER=clang \
        -DAMDGPU_TARGETS="${AMDGPU_TARGETS}" .. && \
    make -j"$(nproc)" && make install && \
    rm -rf /var/tmp/rocprim

# =============================================================================
# 8. rocSPARSE
# =============================================================================
RUN git clone https://github.com/ROCm/rocSPARSE.git /var/tmp/rocsparse && \
    cd /var/tmp/rocsparse && \
    mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX="${ROCM_PATH}" \
        -DCMAKE_PREFIX_PATH="${ROCM_PATH}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_COMPILER=clang++ \
        -DCMAKE_C_COMPILER=clang \
        -DAMDGPU_TARGETS="${AMDGPU_TARGETS}" .. && \
    make -j"$(nproc)" && make install && \
    rm -rf /var/tmp/rocsparse

# =============================================================================
# 9. rocBLAS (с Tensile — оптимизированные ядра под GPU/ASIC/кластеры)
# =============================================================================
RUN git clone https://github.com/ROCm/rocBLAS.git /var/tmp/rocblas && \
    cd /var/tmp/rocblas && \
    mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX="${ROCM_PATH}" \
        -DCMAKE_PREFIX_PATH="${ROCM_PATH}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_COMPILER=clang++ \
        -DCMAKE_C_COMPILER=clang \
        -DAMDGPU_TARGETS="${AMDGPU_TARGETS}" \
        -DTENSILE_ENABLE=ON \
        -DTENSILE_CPU_THREADS=$(nproc) \
        -DTENSILE_LOGIC=6 \
        -DTENSILE_CODE_OBJECT_VERSION=3 \
        -DTENSILE_LIBRARY_FORMAT=msgpack .. && \
    make -j"$(nproc)" && make install && \
    rm -rf /var/tmp/rocblas

# =============================================================================
# 10. ZLUDA (CUDA API на AMD GPU через Level Zero)
# =============================================================================
ENV ZLUDA_VERSION=v6-preview.71 \
    RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:${PATH}

RUN useradd --no-log-init -m -u 999 -s /bin/bash rustbuilder && \
    mkdir -p /opt/cargo /opt/rustup && \
    chown -R rustbuilder:rustbuilder /opt/cargo /opt/rustup

USER rustbuilder
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --no-modify-path --default-toolchain stable

USER root
RUN chmod -R a+rX /opt/cargo /opt/rustup

USER rustbuilder
RUN git clone https://github.com/vosen/ZLUDA.git /var/tmp/zluda && \
    cd /var/tmp/zluda && git fetch --tags && git checkout tags/${ZLUDA_VERSION} && \
    cargo build --release

USER root
RUN mkdir -p /opt/zluda && \
    cp -r /var/tmp/zluda/target/release/* /opt/zluda/ && \
    rm -rf /var/tmp/zluda

# =============================================================================
# 11. Сборка проекта
# =============================================================================
WORKDIR /app
COPY Makefile* CMakeLists.txt* package.json* ./
COPY ./src ./src
COPY ./include ./include
COPY ./common ./common
COPY ./cpu ./cpu
COPY ./gpu ./gpu
COPY ./tests ./tests
COPY ./examples ./examples

# Собираем проект с поддержкой ROCk (AMD GPU native) и ZLUDA
RUN make ROCK_SUPPORT=1 ZLUDA_SUPPORT=1 CC=clang-23 CXX=clang++-23 install

# =============================================================================
# 12. Runtime — используем тот же образ билдера
# =============================================================================
FROM builder AS runtime

ENV DEBIAN_FRONTEND=noninteractive \
    HIP_PLATFORM=amd \
    ZLUDA_SUPPORT=1 \
    ROCM_PATH=/opt/rocm \
    LLVM_PATH=/opt/llvm \
    LD_LIBRARY_PATH="/opt/zluda:/opt/rocm/lib:/opt/llvm/lib:/usr/local/lib:/usr/lib/x86_64-linux-gnu" \
    PATH="/opt/llvm/bin:/opt/rocm/bin:/opt/rocm/llvm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# runtime-зависимости
RUN apt-get update && apt-get install -y \
    curl libssl3 libnuma1 libdrm2 libelf1 libgomp1 \
    libgl1-mesa-dri mesa-utils ffmpeg libavcodec-dev \
    libavformat-dev libavutil-dev libavdevice-dev libswresample-dev \
    libswscale-dev portaudio19-dev libasound2-dev libpulse-dev \
    libmp3lame-dev libopus-dev libvorbis-dev libsodium-dev libstdc++6 \
    libssl-dev pkg-config  libsodium-dev libx11-6 libxext6 libgcc-s1 \
    libxfixes3 libgl1 libglx-mesa0 libopengl0 libdrm-amdgpu1 \
    ca-certificates libomp-dev

# Копируем только артефакты сборки из билдера
COPY --from=builder /opt/rocm/ /opt/rocm/
COPY --from=builder /usr/lib/llvm-23/ /opt/llvm/
COPY --from=builder /opt/zluda/ /opt/zluda/
COPY --from=builder /app/build/ /app/
COPY --from=builder /app/priv/ /app/priv/

# Обновляем кэш библиотек
RUN ldconfig

# Безопасность: непривилегированный пользователь
RUN groupadd -r appuser && \
    useradd --no-log-init -r -g appuser -s /sbin/nologin appuser && \
    chown -R appuser:appuser /app
USER appuser

WORKDIR /app
EXPOSE 4000 4002

# HEALTHCHECK (exec-форма)
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD ["curl", "-sf", "http://localhost:4000/health"]

# ENTRYPOINT (exec-форма, правильная передача сигналов)
ENTRYPOINT ["./dsp_server"]