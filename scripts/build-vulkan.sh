#!/usr/bin/env bash
# Build CachyLLama with the Vulkan (RADV) backend. No ROCm SDK required.
# Env: CACHYLLAMA_REF (default main), LLAMA_DIR (default ./llama.cpp).
set -euo pipefail

self_test() {
  # No mapping logic to test here; assert the default LLAMA_DIR resolves.
  local pass=0 fail=0
  [ "${LLAMA_DIR:-./llama.cpp}" = "./llama.cpp" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL default LLAMA_DIR"; }
  echo "self-test: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

if [ "${1:-}" = "--self-test" ]; then self_test; exit 0; fi

CACHYLLAMA_REF="${CACHYLLAMA_REF:-main}"
LLAMA_DIR="${LLAMA_DIR:-./llama.cpp}"

cd "$LLAMA_DIR"
mkdir -p build
cd build

cmake .. -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DGGML_HIP=OFF \
  -DGGML_HIPBLAS=OFF \
  -DGGML_VULKAN=ON \
  -DGGML_CPU=ON \
  -DGGML_NATIVE=OFF \
  -DLLAMA_BUILD_SERVER=ON \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_EXAMPLES=ON

cmake --build . -j "$(nproc)"