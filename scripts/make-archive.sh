#!/usr/bin/env bash
# Pack build/bin into the canonical release archive name.
# Env: TAG (required), BACKEND (rocm|vulkan), GFX_TARGET (e.g. gfx1151),
#      BUILD_BIN (default ./llama.cpp/build/bin), OUT_DIR (default .).
set -euo pipefail

archive_name() {
  # cachy-<tag>-ubuntu-<backend>-<gfx>-x64.tar.zst
  printf 'cachy-%s-ubuntu-%s-%s-x64.tar.zst\n' "$1" "$2" "$3"
}

self_test() {
  local pass=0 fail=0 got
  got="$(archive_name b1042 rocm gfx1151)"
  [ "$got" = "cachy-b1042-ubuntu-rocm-gfx1151-x64.tar.zst" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL nightly name: $got"; }
  got="$(archive_name v1.0.0 vulkan gfx110X)"
  [ "$got" = "cachy-v1.0.0-ubuntu-vulkan-gfx110X-x64.tar.zst" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL tag name: $got"; }
  echo "self-test: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

if [ "${1:-}" = "--self-test" ]; then self_test; exit 0; fi

: "${TAG:?TAG is required}"
: "${BACKEND:?BACKEND is required (rocm|vulkan)}"
: "${GFX_TARGET:?GFX_TARGET is required}"
BUILD_BIN="${BUILD_BIN:-./llama.cpp/build/bin}"
OUT_DIR="${OUT_DIR:-.}"

archive="$(archive_name "$TAG" "$BACKEND" "$GFX_TARGET")"
tar --use-compress-program=zstd -cf "$OUT_DIR/$archive" -C "$BUILD_BIN" .
echo "Created $OUT_DIR/$archive"