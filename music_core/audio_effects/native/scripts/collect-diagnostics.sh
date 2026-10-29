#!/bin/bash
# =============================================================================
# Collect Diagnostics — сбор информации для техподдержки
# =============================================================================
# Использование:
#   sudo ./scripts/collect-diagnostics.sh
#   # или внутри контейнера:
#   docker compose exec dsp-runtime ./scripts/collect-diagnostics.sh
# =============================================================================

set -euo pipefail
DIAG_DIR="/tmp/diag-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DIAG_DIR"

echo "📦 Collecting diagnostics to $DIAG_DIR ..."

# 1. Логи контейнера
if command -v docker &>/dev/null; then
    echo "  → docker compose logs" >&2
    docker compose logs dsp-runtime > "$DIAG_DIR/docker-logs.txt" 2>/dev/null || \
        docker logs dsp-runtime > "$DIAG_DIR/docker-logs.txt" 2>/dev/null || true

    echo "  → docker inspect" >&2
    docker inspect dsp-runtime > "$DIAG_DIR/docker-inspect.json" 2>/dev/null || true
fi

# 2. GPU / ROCm
echo "  → rocm-smi" >&2
rocm-smi --showallinfo > "$DIAG_DIR/rocm-smi.txt" 2>/dev/null || \
    echo "rocm-smi not available" > "$DIAG_DIR/rocm-smi.txt"

echo "  → /dev/kfd" >&2
ls -la /dev/kfd > "$DIAG_DIR/kfd.txt" 2>/dev/null || \
    echo "/dev/kfd not found" > "$DIAG_DIR/kfd.txt"

echo "  → rocminfo" >&2
rocminfo > "$DIAG_DIR/rocminfo.txt" 2>/dev/null || \
    echo "rocminfo not available" > "$DIAG_DIR/rocminfo.txt"

echo "  → kernel messages (amdgpu)" >&2
dmesg | grep -i 'kfd\|amdgpu\|zluda' > "$DIAG_DIR/dmesg-gpu.txt" 2>/dev/null || true

# 3. Артефакты DSP
echo "  → shared libraries" >&2
ls -la /app/priv/native/ > "$DIAG_DIR/artifacts-rust.txt" 2>/dev/null || \
    echo "/app/priv/native/ not found" > "$DIAG_DIR/artifacts-rust.txt"
ls -la /usr/local/lib/libdsp.so > "$DIAG_DIR/artifacts-c.txt" 2>/dev/null || \
    echo "libdsp.so not found" > "$DIAG_DIR/artifacts-c.txt"
ls -la /opt/zluda/ > "$DIAG_DIR/artifacts-zluda.txt" 2>/dev/null || \
    echo "/opt/zluda/ not found" > "$DIAG_DIR/artifacts-zluda.txt"

echo "  → ldconfig" >&2
ldconfig -p | grep -iE 'dsp|rocm|zluda|audio' > "$DIAG_DIR/ldconfig.txt" 2>/dev/null || true

# 4. Системная информация
echo "  → system info" >&2
uname -a > "$DIAG_DIR/uname.txt" 2>/dev/null || true
cat /etc/os-release > "$DIAG_DIR/os-release.txt" 2>/dev/null || true
free -h > "$DIAG_DIR/memory.txt" 2>/dev/null || true
lscpu > "$DIAG_DIR/cpu.txt" 2>/dev/null || true
lspci | grep -i 'VGA\|3D\|AMD\|NVIDIA' > "$DIAG_DIR/gpu-pci.txt" 2>/dev/null || true

# 5. Healthcheck
echo "  → healthcheck" >&2
curl -sf http://localhost:4000/health > "$DIAG_DIR/healthcheck.txt" 2>/dev/null || \
    echo "healthcheck endpoint not available (port 4000)" > "$DIAG_DIR/healthcheck.txt"

# 6. Docker stats
echo "  → docker stats" >&2
docker stats --no-stream dsp-runtime > "$DIAG_DIR/docker-stats.txt" 2>/dev/null || true

# Упаковка
ARCHIVE="/tmp/diag-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czf "$ARCHIVE" -C "$(dirname "$DIAG_DIR")" "$(basename "$DIAG_DIR")" 2>/dev/null
rm -rf "$DIAG_DIR"

echo ""
echo "✅ Diagnostics saved to: $ARCHIVE"
echo "   Size: $(du -h "$ARCHIVE" | cut -f1)"
echo ""
echo "📧 Send this file to support."