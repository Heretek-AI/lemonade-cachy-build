#!/usr/bin/env bash
# Copy the ROCm runtime libs needed to run llama-server without a system ROCm,
# then set RPATH=$ORIGIN so the bundle is self-contained.
# Env: ROCM_PATH (default /opt/rocm), BUILD_BIN (default ./llama.cpp/build/bin).
set -euo pipefail

# Libs copied from $ROCM_PATH/lib (and rocm_sysdeps / llvm subdirs).
# Kept in sync with lemonade-sdk/llamacpp-rocm's ubuntu bundle step.
LIBS=(
  libhipblas librocblas libamdhip64 librocsolver libroctx64 libhipblaslt
  librocm_sysdeps_liblzma librocprofiler-register libamd_comgr
  libamd_comgr_loader libhsa-runtime64 librocm_sysdeps_numa librocroller
  librocm_kpack librocm_sysdeps_z librocm_sysdeps_zstd
  libLLVM libclang-cpp librocm_sysdeps_elf librocm_sysdeps_drm
  librocm_sysdeps_drm_amdgpu librocm_sysdeps_bz2
)
LIB_DIRS=(rocblas/library hipblaslt/library)

self_test() {
  local pass=0 fail=0
  [ "${#LIBS[@]}" -ge 20 ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL lib count"; }
  printf '%s\n' "${LIBS[@]}" | grep -qx libhipblas && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL libhipblas missing"; }
  printf '%s\n' "${LIBS[@]}" | grep -qx librocblas && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL librocblas missing"; }
  printf '%s\n' "${LIB_DIRS[@]}" | grep -qx rocblas/library && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL rocblas/library missing"; }
  echo "self-test: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

if [ "${1:-}" = "--self-test" ]; then self_test; exit 0; fi

ROCM_PATH="${ROCM_PATH:-/opt/rocm}"
BUILD_BIN="${BUILD_BIN:-./llama.cpp/build/bin}"

copy_lib() {
  local name="$1"
  # Try lib/, lib/rocm_sysdeps/lib/, lib/llvm/lib/.
  for sub in lib "lib/rocm_sysdeps/lib" "lib/llvm/lib"; do
    cp -v "$ROCM_PATH/$sub/$name".so* "$BUILD_BIN/" 2>/dev/null && return 0
  done
  echo "warning: $name.so* not found in $ROCM_PATH"
}

mkdir -p "$BUILD_BIN"

for name in "${LIBS[@]}"; do copy_lib "$name"; done

# Kernel dirs.
for d in "${LIB_DIRS[@]}"; do
  if [ -d "$ROCM_PATH/lib/$d" ]; then
    mkdir -p "$BUILD_BIN/$(dirname "$d")"
    cp -r "$ROCM_PATH/lib/$d" "$BUILD_BIN/$(dirname "$d")/"
  else
    echo "warning: $ROCM_PATH/lib/$d not found"
  fi
done

# RPATH = $ORIGIN so the bundle finds its own libs.
for f in "$BUILD_BIN"/*.so* "$BUILD_BIN"/llama-*; do
  [ -f "$f" ] && [ ! -L "$f" ] && patchelf --set-rpath '$ORIGIN' "$f" 2>/dev/null || true
done

echo "Bundled ROCm libs into $BUILD_BIN"