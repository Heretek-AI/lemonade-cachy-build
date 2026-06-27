#!/usr/bin/env bash
# Build CachyLLama with ROCm (HIP) for one gfx target.
# Env: CACHYLLAMA_REF (default main), GFX_TARGET (required for build),
#      ROCM_PATH (default /opt/rocm), LLAMA_DIR (default ./llama.cpp).
set -euo pipefail

map_gfx() {
  case "$1" in
    gfx110X) echo "gfx1100;gfx1101;gfx1102;gfx1103" ;;
    gfx1150) echo "gfx1150" ;;
    gfx1151) echo "gfx1151" ;;
    gfx120X) echo "gfx1200;gfx1201" ;;
    gfx103X) echo "gfx1030;gfx1031;gfx1032;gfx1034" ;;
    gfx90a)  echo "gfx90a"  ;;
    gfx908)  echo "gfx908"  ;;
    *)       echo "$1" ;;
  esac
}

self_test() {
  local pass=0 fail=0
  check() {
    local input="$1" expected="$2" got
    got="$(map_gfx "$input")"
    if [ "$got" = "$expected" ]; then pass=$((pass+1));
    else fail=$((fail+1)); echo "FAIL map_gfx $input: got $got want $expected"; fi
  }
  check gfx110X "gfx1100;gfx1101;gfx1102;gfx1103"
  check gfx1151 "gfx1151"
  check gfx120X "gfx1200;gfx1201"
  check gfx103X "gfx1030;gfx1031;gfx1032;gfx1034"
  check gfx90a  "gfx90a"
  check gfx1150 "gfx1150"
  echo "self-test: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

if [ "${1:-}" = "--self-test" ]; then self_test; exit 0; fi

: "${GFX_TARGET:?GFX_TARGET is required for a ROCm build}"
CACHYLLAMA_REF="${CACHYLLAMA_REF:-main}"
ROCM_PATH="${ROCM_PATH:-/opt/rocm}"
LLAMA_DIR="${LLAMA_DIR:-./llama.cpp}"

mapped="$(map_gfx "$GFX_TARGET")"
echo "HIP GPU_TARGETS: $mapped"

cd "$LLAMA_DIR"
mkdir -p build
cd build

cmake .. -G Ninja \
  -DCMAKE_C_COMPILER="$ROCM_PATH/llvm/bin/clang" \
  -DCMAKE_CXX_COMPILER="$ROCM_PATH/llvm/bin/clang++" \
  -DCMAKE_CXX_FLAGS="-I$ROCM_PATH/include" \
  -DCMAKE_BUILD_TYPE=Release \
  -DGPU_TARGETS="$mapped" \
  -DBUILD_SHARED_LIBS=ON \
  -DLLAMA_BUILD_TESTS=OFF \
  -DGGML_HIP=ON \
  -DGGML_OPENMP=OFF \
  -DGGML_RPC=ON \
  -DGGML_HIP_ROCWMMA_FATTN=OFF \
  -DLLAMA_BUILD_BORINGSSL=ON \
  -DGGML_NATIVE=OFF \
  -DGGML_STATIC=OFF \
  -DCMAKE_SYSTEM_NAME=Linux

cmake --build . -j "$(nproc)"