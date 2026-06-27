# lemonade-cachy-build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Standalone repo `Heretek-AI/lemonade-cachy-build` that CI-builds `fewtarius/CachyLLama` for AMD ROCm (Ubuntu), shipping per-gfx per-backend `tar.zst` release archives with bundled ROCm 7 runtime, drop-in for Lemonade.

**Architecture:** GitHub Actions workflow (`build.yml`) on hosted `ubuntu-22.04` runners: `prepare-matrix` → `build-ubuntu` (matrix of gfx × backend) → `create-release`. Build logic lives in shell scripts under `scripts/` so it runs identically in CI and locally. ROCm jobs pull the TheRock SDK nightly for HIP cross-compile; Vulkan jobs need no SDK. A second workflow (`test.yml`) downloads a released archive and runs `llama-server --version`.

**Tech Stack:** Bash, CMake + Ninja, TheRock ROCm SDK, GitHub Actions, `gh` CLI, `patchelf`, `zstd`.

## Global Constraints

- Source tree: `fewtarius/CachyLLama`, shallow clone at pinned commit (`CACHYLLAMA_REF`), NOT a submodule.
- OS: Ubuntu only (no Windows in v1).
- Backends: `rocm` and `vulkan`. gfx90a/gfx908 get ROCm only (CDNA; no Vulkan jobs).
- gfx matrix: `gfx110X,gfx1150,gfx1151,gfx120X,gfx103X,gfx90a,gfx908`.
- Runner: GitHub-hosted `ubuntu-22.04`, no GPU. Inference is never smoke-tested in CI.
- ROCm SDK: TheRock nightlies from `https://rocm.nightlies.amd.com/tarball-multi-arch`, streamed to `/opt/rocm`, no auth.
- ROCm build flags match llamacpp-rocm: `GGML_HIP=ON` + `GPU_TARGETS=<mapped>` (NOT CachyLLama's `CMAKE_HIP_ARCHITECTURES`).
- Archive name: `cachy-${TAG}-ubuntu-${backend}-${gfx}-x64.tar.zst`.
- Releases: nightly → sequential `b####` prerelease; git tag `v*` → stable using that tag.
- Permissions: `contents: write` on release job; `GITHUB_TOKEN` (or `GH_TOKEN` secret); no other secrets.
- Every non-trivial script ships a `--self-test` mode (asserts) per the project's lazy-code-with-a-check rule.
- Commit after every task. Repo root is the current working directory (will be pushed to `Heretek-AI/lemonade-cachy-build`).

---

## File Structure

| File | Responsibility |
|---|---|
| `.gitignore` | Ignore clone/build/archive scratch |
| `README.md` | What it is, supported devices, download+run, automated builds |
| `docs/build.md` | Local repro, env vars, add a gfx target, cut a release, manual GPU validation |
| `scripts/build-rocm.sh` | Configure + build CachyLLama with ROCm (HIP) for a mapped gfx target |
| `scripts/build-vulkan.sh` | Configure + build CachyLLama with Vulkan (RADV) |
| `scripts/bundle-rocm-libs.sh` | Copy ROCm runtime libs into build/bin + `patchelf --set-rpath '$ORIGIN'` |
| `scripts/make-archive.sh` | `tar.zst` the build/bin dir with the canonical archive name |
| `.github/workflows/build.yml` | Main pipeline: prepare-matrix → build-ubuntu → create-release |
| `.github/workflows/test.yml` | Download a released archive, run `llama-server --version` |

---

### Task 1: Repository skeleton

**Files:**
- Create: `.gitignore`
- Create: `README.md` (stub — finalized in Task 8)
- Create: `docs/build.md` (stub — finalized in Task 8)
- Create: `scripts/.gitkeep`
- Create: `.github/workflows/.gitkeep`

**Interfaces:**
- Consumes: none
- Produces: directory layout the rest of the plan writes into

- [ ] **Step 1: Create `.gitignore`**

```gitignore
# CachyLLama source clone (shallow, created by build scripts)
llama.cpp/
CachyLLama/

# Build output
build/
bin/

# Archives
*.tar.zst
*.tar.gz
*.zip

# Local ROCm SDK scratch
rocm/
opt-rocm/

# OS / editor
.DS_Store
*.swp
```

- [ ] **Step 2: Create `README.md` stub**

```markdown
# lemonade-cachy-build

Fresh builds of [CachyLLama](https://github.com/fewtarius/CachyLLama) (a
[llama.cpp](https://github.com/ggml-org/llama.cpp) fork) with AMD ROCm™ 7
acceleration, built for [Lemonade](https://github.com/lemonade-sdk/lemonade).

> Full README coming in Task 8. See `docs/build.md` for the build pipeline.
```

- [ ] **Step 3: Create `docs/build.md` stub**

```markdown
# Build pipeline

> Full docs coming in Task 8.
```

- [ ] **Step 4: Create keepfiles for empty dirs**

```bash
mkdir -p scripts .github/workflows
touch scripts/.gitkeep .github/workflows/.gitkeep
```

- [ ] **Step 5: Commit**

```bash
git add .gitignore README.md docs/build.md scripts/.gitkeep .github/workflows/.gitkeep
git commit -m "chore: repo skeleton"
```

---

### Task 2: `scripts/build-rocm.sh`

**Files:**
- Create: `scripts/build-rocm.sh`
- Test: self-test mode inside the same file (`scripts/build-rocm.sh --self-test`)

**Interfaces:**
- Consumes: env `CACHYLLAMA_REF` (commit/tag/branch, default `main`), `GFX_TARGET` (e.g. `gfx1151`), `ROCM_PATH` (default `/opt/rocm`), `LLAMA_DIR` (default `./llama.cpp`).
- Produces: built binaries in `$LLAMA_DIR/build/bin/`. Exits 0 on success. Prints the mapped HIP `GPU_TARGETS` string to stdout on `--self-test`.

- [ ] **Step 1: Write the script with a self-test for the gfx mapping**

Create `scripts/build-rocm.sh`:

```bash
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
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/build-rocm.sh
```

- [ ] **Step 3: Run the self-test**

Run: `./scripts/build-rocm.sh --self-test`
Expected: `self-test: 6 passed, 0 failed`, exit 0.

- [ ] **Step 4: Commit**

```bash
git add scripts/build-rocm.sh
git commit -m "feat: build-rocm.sh with gfx mapping self-test"
```

---

### Task 3: `scripts/build-vulkan.sh`

**Files:**
- Create: `scripts/build-vulkan.sh`
- Test: self-test mode inside the same file

**Interfaces:**
- Consumes: env `CACHYLLAMA_REF` (default `main`), `LLAMA_DIR` (default `./llama.cpp`). No `GFX_TARGET` needed — Vulkan kernels are not gfx-specific at compile time.
- Produces: built binaries in `$LLAMA_DIR/build/bin/`. Exits 0 on success.

- [ ] **Step 1: Write the script with a self-test**

Create `scripts/build-vulkan.sh`:

```bash
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
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/build-vulkan.sh
```

- [ ] **Step 3: Run the self-test**

Run: `./scripts/build-vulkan.sh --self-test`
Expected: `self-test: 1 passed, 0 failed`, exit 0.

- [ ] **Step 4: Commit**

```bash
git add scripts/build-vulkan.sh
git commit -m "feat: build-vulkan.sh"
```

---

### Task 4: `scripts/bundle-rocm-libs.sh`

**Files:**
- Create: `scripts/bundle-rocm-libs.sh`
- Test: self-test mode (asserts the lib list matches the spec)

**Interfaces:**
- Consumes: env `ROCM_PATH` (default `/opt/rocm`), `BUILD_BIN` (default `./llama.cpp/build/bin`).
- Produces: ROCm runtime libs + `rocblas/library` + `hipblaslt/library` copied into `$BUILD_BIN`; RPATH set to `$ORIGIN` on every `.so*` and `llama-*` file there.

- [ ] **Step 1: Write the script with a self-test for the lib list**

Create `scripts/bundle-rocm-libs.sh`:

```bash
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
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/bundle-rocm-libs.sh
```

- [ ] **Step 3: Run the self-test**

Run: `./scripts/bundle-rocm-libs.sh --self-test`
Expected: `self-test: 4 passed, 0 failed`, exit 0.

- [ ] **Step 4: Commit**

```bash
git add scripts/bundle-rocm-libs.sh
git commit -m "feat: bundle-rocm-libs.sh"
```

---

### Task 5: `scripts/make-archive.sh`

**Files:**
- Create: `scripts/make-archive.sh`
- Test: self-test mode (asserts archive name format)

**Interfaces:**
- Consumes: env `TAG` (required, e.g. `b1042` or `v1.0.0`), `BACKEND` (`rocm` | `vulkan`), `GFX_TARGET` (e.g. `gfx1151`), `BUILD_BIN` (default `./llama.cpp/build/bin`), `OUT_DIR` (default `.`).
- Produces: `$OUT_DIR/cachy-${TAG}-ubuntu-${BACKEND}-${GFX_TARGET}-x64.tar.zst`.

- [ ] **Step 1: Write the script with a self-test for the archive name**

Create `scripts/make-archive.sh`:

```bash
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
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/make-archive.sh
```

- [ ] **Step 3: Run the self-test**

Run: `./scripts/make-archive.sh --self-test`
Expected: `self-test: 2 passed, 0 failed`, exit 0.

- [ ] **Step 4: Commit**

```bash
git add scripts/make-archive.sh
git commit -m "feat: make-archive.sh with canonical name self-test"
```

---

### Task 6: `.github/workflows/build.yml`

**Files:**
- Create: `.github/workflows/build.yml`
- Remove: `scripts/.gitkeep`, `.github/workflows/.gitkeep` (no longer empty)

**Interfaces:**
- Consumes: `scripts/build-rocm.sh`, `scripts/build-vulkan.sh`, `scripts/bundle-rocm-libs.sh`, `scripts/make-archive.sh` (Tasks 2–5).
- Produces: GitHub Release archives. Nightly `b####` prereleases; `v*` tags stable.

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/build.yml`:

```yaml
name: Build CachyLLama + ROCm

on:
  workflow_dispatch:
    inputs:
      gfx_target:
        description: 'AMD GPU targets (comma-separated)'
        required: false
        default: 'gfx1151,gfx1150,gfx120X,gfx110X,gfx103X,gfx90a,gfx908'
      backend:
        description: 'Backend: rocm, vulkan, or both'
        required: false
        default: 'both'
      cachyllama_ref:
        description: 'CachyLLama ref (tag/branch/commit) or "main"'
        required: false
        default: 'main'
      rocm_version:
        description: 'TheRock ROCm version or "latest"'
        required: false
        default: 'latest'
      create_release:
        description: 'Create a GitHub release after successful build'
        required: false
        default: true
        type: boolean

  schedule:
    # ~07:17 UTC, off-peak.
    - cron: '17 7 * * *'

  push:
    tags:
      - 'v*'

env:
  GFX_TARGETS: ${{ github.event.inputs.gfx_target || 'gfx1151,gfx1150,gfx120X,gfx110X,gfx103X,gfx90a,gfx908' }}
  BACKEND: ${{ github.event.inputs.backend || 'both' }}
  CACHYLLAMA_REF: ${{ github.event.inputs.cachyllama_ref || 'main' }}
  ROCM_VERSION: ${{ github.event.inputs.rocm_version || 'latest' }}

jobs:
  prepare-matrix:
    runs-on: ubuntu-22.04
    outputs:
      ubuntu_matrix: ${{ steps.set-matrix.outputs.ubuntu_matrix }}
    steps:
      - id: set-matrix
        run: |
          targets="${{ env.GFX_TARGETS }}"
          backend="${{ env.BACKEND }}"
          # gfx90a / gfx908 are CDNA — ROCm only, skip Vulkan.
          cdna="gfx90a gfx908"
          rows='[]'
          for gfx in $(echo "$targets" | tr ',' ' '); do
            for b in rocm vulkan; do
              if [ "$backend" != "both" ] && [ "$backend" != "$b" ]; then continue; fi
              if echo "$cdna" | grep -qw "$gfx" && [ "$b" = "vulkan" ]; then continue; fi
              rows=$(echo "$rows" | jq -c --arg g "$gfx" --arg b "$b" '. + [{gfx_target:$g, backend:$b}]')
            done
          done
          ubuntu_matrix=$(echo "$rows" | jq -c '{include: .}')
          echo "ubuntu_matrix=$ubuntu_matrix" >> "$GITHUB_OUTPUT"
          echo "Matrix: $ubuntu_matrix"

  build-ubuntu:
    runs-on: ubuntu-22.04
    needs: prepare-matrix
    strategy:
      matrix: ${{ fromJson(needs.prepare-matrix.outputs.ubuntu_matrix) }}
      fail-fast: false
    outputs:
      rocm_version: ${{ steps.set-outputs.outputs.rocm_version }}
      cachyllama_commit: ${{ steps.set-outputs.outputs.cachyllama_commit }}
    steps:
      - name: Checkout this repo
        uses: actions/checkout@v4

      - name: Free disk space
        run: curl -fsSL https://raw.githubusercontent.com/kou/arrow/e49d8ae15583ceff03237571569099a6ad62be32/ci/scripts/util_free_space.sh | bash

      - name: Install build deps
        run: |
          sudo apt-get update
          sudo apt-get install -y cmake ninja-build unzip curl zstd patchelf jq

      - name: Download TheRock ROCm SDK (ROCm backend only)
        if: matrix.backend == 'rocm'
        run: |
          rocm_version="${{ env.ROCM_VERSION }}"
          gfx="${{ matrix.gfx_target }}"
          s3_target="$gfx"
          case "$gfx" in
            gfx103X|gfx110X|gfx120X) s3_target="${gfx}-all" ;;
          esac
          base_url="https://rocm.nightlies.amd.com/tarball-multi-arch"
          if [ "$rocm_version" = "latest" ]; then
            prefix="therock-dist-linux-${s3_target}-"
            files_json=$(curl -s "$base_url/" | tr '\n' ' ' | grep -oP 'const files = \K\[.*?\](?=\s*;)')
            latest_file=$(echo "$files_json" | jq -r --arg p "$prefix" \
              '[.[] | select(.name | startswith($p)) | select(.name | test("[0-9]{8}\\.tar\\.gz$"))] | sort_by(.name | capture("(?<d>[0-9]{8})\\.tar\\.gz$").d) | last | .name // empty')
            [ -n "$latest_file" ] || { echo "No tarball for $prefix"; exit 1; }
            rocm_version=$(echo "$latest_file" | grep -oP 'therock-dist-linux-'"$s3_target"'-\K[0-9]+\.[0-9]+\.[0-9]+(a|rc)[0-9]+')
            rocm_url="$base_url/$latest_file"
          else
            rocm_url="$base_url/therock-dist-linux-${s3_target}-${rocm_version}.tar.gz"
          fi
          echo "DETECTED_ROCM_VERSION=$rocm_version" >> "$GITHUB_ENV"
          sudo mkdir -p /opt/rocm
          curl -sL "$rocm_url" | sudo tar --use-compress-program=gzip -xf - -C /opt/rocm --strip-components=1

      - name: Set ROCm env (ROCm backend only)
        if: matrix.backend == 'rocm'
        run: |
          echo "HIP_PATH=/opt/rocm" >> "$GITHUB_ENV"
          echo "ROCM_PATH=/opt/rocm" >> "$GITHUB_ENV"
          echo "HIP_CLANG_PATH=/opt/rocm/llvm/bin" >> "$GITHUB_ENV"
          echo "/opt/rocm/bin:/opt/rocm/llvm/bin" >> "$GITHUB_PATH"
          echo "LD_LIBRARY_PATH=/opt/rocm/lib:/opt/rocm/lib64:/opt/rocm/llvm/lib" >> "$GITHUB_ENV"

      - name: Clone CachyLLama
        run: |
          ref="${{ env.CACHYLLAMA_REF }}"
          git clone --depth 1 --single-branch --branch "$ref" https://github.com/fewtarius/CachyLLama.git llama.cpp 2>/dev/null \
            || git clone --depth 1 https://github.com/fewtarius/CachyLLama.git llama.cpp
          cd llama.cpp
          echo "CACHYLLAMA_COMMIT=$(git rev-parse --short=5 HEAD)" >> "$GITHUB_ENV"
          git log --oneline -1

      - name: Build (ROCm)
        if: matrix.backend == 'rocm'
        env:
          GFX_TARGET: ${{ matrix.gfx_target }}
          ROCM_PATH: /opt/rocm
          LLAMA_DIR: ./llama.cpp
        run: ./scripts/build-rocm.sh

      - name: Build (Vulkan)
        if: matrix.backend == 'vulkan'
        env:
          LLAMA_DIR: ./llama.cpp
        run: ./scripts/build-vulkan.sh

      - name: Bundle ROCm libs
        if: matrix.backend == 'rocm'
        env:
          ROCM_PATH: /opt/rocm
          BUILD_BIN: ./llama.cpp/build/bin
        run: ./scripts/bundle-rocm-libs.sh

      - name: Smoke check — binary runs + links
        if: always()
        run: |
          cd llama.cpp/build/bin
          if [ -x llama-server ]; then
            ./llama-server --version
            if ldd llama-server 2>&1 | grep -q "not found"; then
              echo "ldd reports missing libs"; exit 1
            fi
          else
            echo "llama-server not found"; exit 1
          fi

      - name: Determine release tag
        id: tag
        run: |
          if [ "${GITHUB_REF_TYPE:-}" = "tag" ]; then
            echo "tag=${GITHUB_REF##*/}" >> "$GITHUB_OUTPUT"
          else
            echo "tag=nightly-pending" >> "$GITHUB_OUTPUT"
          fi

      - name: Make archive
        env:
          TAG: ${{ steps.tag.outputs.tag }}
          BACKEND: ${{ matrix.backend }}
          GFX_TARGET: ${{ matrix.gfx_target }}
          BUILD_BIN: ./llama.cpp/build/bin
        run: ./scripts/make-archive.sh

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: cachy-ubuntu-${{ matrix.backend }}-${{ matrix.gfx_target }}-x64
          path: cachy-*-ubuntu-${{ matrix.backend }}-${{ matrix.gfx_target }}-x64.tar.zst
          retention-days: 30

      - id: set-outputs
        if: always()
        run: |
          echo "rocm_version=${DETECTED_ROCM_VERSION:-none}" >> "$GITHUB_OUTPUT"
          echo "cachyllama_commit=${CACHYLLAMA_COMMIT:-none}" >> "$GITHUB_OUTPUT"

  create-release:
    needs: [prepare-matrix, build-ubuntu]
    runs-on: ubuntu-22.04
    if: always() && needs.build-ubuntu.result == 'success'
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4

      - name: Download all artifacts
        uses: actions/download-artifact@v4
        with:
          path: ./all-artifacts

      - name: Resolve release tag
        id: rel
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          if [ "${GITHUB_REF_TYPE:-}" = "tag" ]; then
            TAG="${GITHUB_REF##*/}"
          else
            existing=$(gh release list --limit 1000 --json tagName --jq '.[].tagName' | grep -E '^b[0-9]{4}$' | sort -V || true)
            if [ -z "$existing" ]; then n=1000; else n=$(( $(echo "$existing" | tail -n1 | sed 's/^b//') + 1 )); fi
            TAG=$(printf "b%04d" "$n")
          fi
          echo "tag=$TAG" >> "$GITHUB_OUTPUT"
          echo "prerelease=$([ "${GITHUB_REF_TYPE:-}" = "tag" ] && echo false || echo true)" >> "$GITHUB_OUTPUT"

      - name: Rename artifacts with tag
        run: |
          TAG="${{ steps.rel.outputs.tag }}"
          mkdir -p out
          for d in all-artifacts/cachy-ubuntu-*; do
            [ -d "$d" ] || continue
            base=$(basename "$d")              # cachy-ubuntu-rocm-gfx1151-x64
            backend=$(echo "$base" | cut -d- -f3)
            gfx=$(echo "$base" | cut -d- -f4)
            mv "$d"/*.tar.zst "out/cachy-${TAG}-ubuntu-${backend}-${gfx}-x64.tar.zst"
          done
          ls -la out

      - name: Create release
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          TAG="${{ steps.rel.outputs.tag }}"
          PRERELEASE="${{ steps.rel.outputs.prerelease }}"
          args=()
          [ "$PRERELEASE" = "true" ] && args+=(--prerelease)
          [ "$PRERELEASE" = "false" ] && args+=(--latest)
          gh release create "$TAG" out/*.tar.zst --title "$TAG" --notes "$(cat <<EOF
          **Build**: $TAG
          **gfx**: ${{ env.GFX_TARGETS }}
          **Backend**: ${{ env.BACKEND }}
          **ROCm**: ${{ needs.build-ubuntu.outputs.rocm_version }}
          **CachyLLama**: ${{ needs.build-ubuntu.outputs.cachyllama_commit }}
          **Built**: $(date -u '+%Y-%m-%d %H:%M UTC')
          EOF
          )" "${args[@]}"
```

- [ ] **Step 2: Remove keepfiles**

```bash
git rm -f scripts/.gitkeep .github/workflows/.gitkeep
```

- [ ] **Step 3: Lint the workflow YAML**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/build.yml')); print('yaml ok')"`
Expected: `yaml ok`. If it errors, fix indentation and re-run.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/build.yml
git commit -m "feat: build.yml workflow (prepare-matrix, build-ubuntu, create-release)"
```

---

### Task 7: `.github/workflows/test.yml`

**Files:**
- Create: `.github/workflows/test.yml`

**Interfaces:**
- Consumes: a published GitHub Release archive.
- Produces: green/red job confirming `llama-server --version` runs from a downloaded archive.

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/test.yml`:

```yaml
name: Test released archive

on:
  workflow_dispatch:
    inputs:
      release_tag:
        description: 'Release tag to test (e.g. b1042 or v1.0.0)'
        required: true
      gfx_target:
        description: 'gfx target'
        required: true
        default: 'gfx1151'
      backend:
        description: 'rocm or vulkan'
        required: true
        default: 'rocm'
  workflow_run:
    workflows: ["Build CachyLLama + ROCm"]
    types: [completed]

jobs:
  test:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v4

      - name: Resolve tag
        id: t
        run: |
          if [ "${{ github.event_name }}" = "workflow_run" ]; then
            echo "tag=${{ github.event.workflow_run.head_branch }}" >> "$GITHUB_OUTPUT"
          else
            echo "tag=${{ github.event.inputs.release_tag }}" >> "$GITHUB_OUTPUT"
          fi

      - name: Download archive
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          TAG="${{ steps.t.outputs.tag }}"
          GFX="${{ github.event.inputs.gfx_target || 'gfx1151' }}"
          BACKEND="${{ github.event.inputs.backend || 'rocm' }}"
          asset="cachy-${TAG}-ubuntu-${BACKEND}-${GFX}-x64.tar.zst"
          gh release download "$TAG" --pattern "$asset" --output "$asset"
          mkdir -p extract && tar --use-compress-program=zstd -xf "$asset" -C extract

      - name: Run llama-server --version
        run: |
          cd extract
          chmod +x llama-server
          ./llama-server --version
          if ldd llama-server 2>&1 | grep -q "not found"; then
            echo "ldd reports missing libs"; exit 1
          fi
```

- [ ] **Step 2: Lint the workflow YAML**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/test.yml')); print('yaml ok')"`
Expected: `yaml ok`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "feat: test.yml — verify released archive runs"
```

---

### Task 8: Finalize `README.md` and `docs/build.md`

**Files:**
- Modify: `README.md` (replace stub from Task 1)
- Modify: `docs/build.md` (replace stub from Task 1)

**Interfaces:**
- Consumes: the workflows and scripts from Tasks 2–7.
- Produces: user-facing docs.

- [ ] **Step 1: Write `README.md`**

```markdown
# lemonade-cachy-build

Fresh builds of [CachyLLama](https://github.com/fewtarius/CachyLLama) (a
[llama.cpp](https://github.com/ggml-org/llama.cpp) fork) with AMD ROCm™ 7
acceleration, built for [Lemonade](https://github.com/lemonade-sdk/lemonade)
and similar apps needing local GPU inference on AMD.

Modeled on [lemonade-sdk/llamacpp-rocm](https://github.com/lemonade-sdk/llamacpp-rocm),
but builds the CachyLLama fork and ships both ROCm and Vulkan backends.

## Supported devices

| GPU target | HIP `GPU_TARGETS` | Backends |
|---|---|---|
| gfx110X | gfx1100;gfx1101;gfx1102;gfx1103 (RDNA3) | rocm, vulkan |
| gfx1150 | gfx1150 (RDNA3.5) | rocm, vulkan |
| gfx1151 | gfx1151 (RDNA3.5) | rocm, vulkan |
| gfx120X | gfx1200;gfx1201 (RDNA4) | rocm, vulkan |
| gfx103X | gfx1030;gfx1031;gfx1032;gfx1034 (RDNA2) | rocm, vulkan |
| gfx90a | gfx90a (CDNA) | rocm |
| gfx908 | gfx908 (CDNA) | rocm |

## Download

1. Grab the archive for your GPU + backend from the
   [latest release](https://github.com/Heretek-AI/lemonade-cachy-build/releases/latest),
   e.g. `cachy-v1.0.0-ubuntu-rocm-gfx1151-x64.tar.zst`.
2. Extract: `tar --use-compress-program=zstd -xf cachy-*.tar.zst`
3. Run: `./llama-server -m model.gguf --port 8080`

ROCm archives include the ROCm 7 runtime — no separate ROCm install needed.
Vulkan archives rely on your system Vulkan (RADV) loader.

## Automated builds

GitHub Actions (`build.yml`) produces:
- **Nightly** (`b####` prereleases) — off-peak, full gfx × backend matrix.
- **Tagged** (`v*` → stable release) — push a tag to cut a release. Pin
  `CACHYLLAMA_REF` in the tag commit for reproducibility.
- **Manual** (`workflow_dispatch`) — override `gfx_target`, `backend`,
  `cachyllama_ref`, `rocm_version`, `create_release`.

`test.yml` downloads a released archive and confirms `llama-server --version`
runs (manual or post-release trigger).

See [`docs/build.md`](docs/build.md) for building locally and cutting releases.

## Credits

- [CachyLLama](https://github.com/fewtarius/CachyLLama) / [llama-ai](https://github.com/fewtarius/llama-ai)
- [TheRock ROCm SDK](https://github.com/ROCm/TheRock)
- [lemonade-sdk/llamacpp-rocm](https://github.com/lemonade-sdk/llamacpp-rocm) — the CI recipe this follows.
```

- [ ] **Step 2: Write `docs/build.md`**

```markdown
# Build pipeline

This repo builds CachyLLama for AMD ROCm on Ubuntu via GitHub Actions. The
build logic lives in `scripts/` so it runs identically in CI and locally.

## Prerequisites (local repro)

- `cmake`, `ninja`, `zstd`, `patchelf`, `jq`
- For the ROCm backend: a TheRock ROCm SDK extracted at `/opt/rocm` (or point
  `ROCM_PATH` at it), or a system ROCm install.
- For the Vulkan backend: `clang`/`clang++` and a Vulkan loader (RADV).

## Build locally

```sh
git clone --depth 1 --branch main https://github.com/fewtarius/CachyLLama.git llama.cpp

# ROCm (gfx1151):
GFX_TARGET=gfx1151 ROCM_PATH=/opt/rocm LLAMA_DIR=./llama.cpp ./scripts/build-rocm.sh
ROCM_PATH=/opt/rocm BUILD_BIN=./llama.cpp/build/bin ./scripts/bundle-rocm-libs.sh

# Vulkan:
LLAMA_DIR=./llama.cpp ./scripts/build-vulkan.sh
```

### Env vars

| Var | Default | Used by |
|---|---|---|
| `CACHYLLAMA_REF` | `main` | clone ref (CI only; locally you clone yourself) |
| `GFX_TARGET` | — (required) | `build-rocm.sh` |
| `ROCM_PATH` | `/opt/rocm` | `build-rocm.sh`, `bundle-rocm-libs.sh` |
| `LLAMA_DIR` | `./llama.cpp` | `build-rocm.sh`, `build-vulkan.sh` |
| `BUILD_BIN` | `./llama.cpp/build/bin` | `bundle-rocm-libs.sh`, `make-archive.sh` |
| `TAG` | — (required) | `make-archive.sh` |
| `BACKEND` | — (required) | `make-archive.sh` |
| `OUT_DIR` | `.` | `make-archive.sh` |

### Self-tests

Each script has a `--self-test` mode:

```sh
./scripts/build-rocm.sh --self-test
./scripts/build-vulkan.sh --self-test
./scripts/bundle-rocm-libs.sh --self-test
./scripts/make-archive.sh --self-test
```

## Manual GPU validation

CI has no GPU. After downloading a release archive, validate on real hardware:

```sh
tar --use-compress-program=zstd -xf cachy-*-rocm-gfx1151-x64.tar.zst -C extract
cd extract && ./llama-server -m /path/to/model.gguf --port 8080
```

Tested on gfx1100 (gfx110X) and gfx1151.

## Add a gfx target

1. Add the gfx to the `map_gfx` case in `scripts/build-rocm.sh` (and its
   self-test).
2. Add it to the `gfx_target` default list in `.github/workflows/build.yml`.
3. If it's CDNA (no Vulkan), add it to the `cdna` skip list in
   `prepare-matrix`.

## Cut a release

```sh
# Pin CACHYLLAMA_REF in the workflow env first, then:
git tag v1.0.0
git push origin v1.0.0
```

The `push: tags: v*` trigger builds and creates a stable release using that
tag. Nightly `b####` prereleases are automatic.
```

- [ ] **Step 3: Commit**

```bash
git add README.md docs/build.md
git commit -m "docs: finalize README and build guide"
```

---

## Self-Review

**1. Spec coverage** — checking each spec section:
- §1 Goal → Task 1 (skeleton) + Task 6 (workflow) deliver the repo. ✓
- §2 Parameters → encoded in `build.yml` env defaults + matrix. ✓
- §3 Repo layout → Tasks 1–8 create every listed file. ✓
- §4 Matrix + job graph → Task 6 `prepare-matrix`/`build-ubuntu`/`create-release`. ✓
- §4 ROCm flags → Task 2 `build-rocm.sh` cmake block. ✓
- §4 Vulkan flags → Task 3 `build-vulkan.sh`. ✓
- §4 lib bundling → Task 4 `bundle-rocm-libs.sh`. ✓
- §5 Release/versioning → Task 6 `create-release` (b#### nightly, v* stable). ✓
- §5 Archive naming → Task 5 `make-archive.sh` (+ self-test asserts the format). ✓
- §6 Testing — in-job `--version` + `ldd` → Task 6 smoke step. ✓ `test.yml` → Task 7. ✓
- §7 Docs → Task 8. ✓
- §8 Deferred (nightly trim, Windows) → out of v1 scope, noted in spec only. ✓

**2. Placeholder scan** — no TBD/TODO/"handle edge cases"; every code step has full content. ✓

**3. Type/consistency check** — script env var names (`GFX_TARGET`, `ROCM_PATH`, `LLAMA_DIR`, `BUILD_BIN`, `TAG`, `BACKEND`, `OUT_DIR`, `CACHYLLAMA_REF`) are identical across the scripts, the workflow env blocks, and the docs table. `map_gfx` mappings match between `build-rocm.sh` and the README table and the `prepare-matrix` cdna skip list. Archive name format `cachy-${TAG}-ubuntu-${backend}-${gfx}-x64.tar.zst` is identical in `make-archive.sh`, the workflow rename step, `test.yml`, and the README example. ✓

No issues found.