# lemonade-cachy-build — design

**Date:** 2026-06-27
**Target repo:** `Heretek-AI/lemonade-cachy-build`
**Status:** approved design, pending implementation plan

## 1. Goal

A standalone repository that uses GitHub Actions to build
[`fewtarius/CachyLLama`](https://github.com/fewtarius/CachyLLama) (the
`llama-ai` fork of llama.cpp) for AMD ROCm, the same way
[`lemonade-sdk/llamacpp-rocm`](https://github.com/lemonade-sdk/llamacpp-rocm)
builds upstream llama.cpp. Output: per-gfx, per-backend Ubuntu `tar.zst`
release archives with bundled ROCm 7 runtime libraries, drop-in for
[Lemonade](https://github.com/lemonade-sdk/lemonade).

## 2. Confirmed parameters

| Parameter | Value |
|---|---|
| Source tree | `fewtarius/CachyLLama`, pinned commit, shallow clone |
| OS targets | Ubuntu only |
| Backends | ROCm (HIPBLAS) **and** Vulkan (RADV) |
| gfx matrix | `gfx110X`, `gfx1150`, `gfx1151`, `gfx120X`, `gfx103X`, `gfx90a`, `gfx908` |
| Owner's hardware | gfx1100 (gfx110X family), gfx1151 |
| Build runner | GitHub-hosted `ubuntu-22.04`, no GPU |
| ROCm source | [TheRock](https://github.com/ROCm/TheRock) SDK nightlies (HIP cross-compile, no system ROCm) |
| Triggers | nightly (off-peak) + `workflow_dispatch` + git tags `v*` |
| Artifact granularity | one `tar.zst` per (gfx, backend) |
| Deliverable | GitHub Release archives (no Docker, no GHCR) |

## 3. Repository layout

```
lemonade-cachy-build/
├── .github/workflows/
│   ├── build.yml          # prepare-matrix → build-ubuntu(rocm+vulkan) → create-release
│   └── test.yml           # downloads a released archive, runs llama-server --version
├── scripts/
│   ├── build-rocm.sh      # cmake ROCm configure+build
│   ├── build-vulkan.sh    # cmake Vulkan configure+build
│   ├── bundle-rocm-libs.sh# copy ROCm runtime libs + patchelf RPATH $ORIGIN
│   └── make-archive.sh    # tar.zst the build/bin dir
├── docs/
│   └── build.md           # how the pipeline works, local repro, adding a gfx target
├── README.md
└── .gitignore
```

Build logic lives in shell scripts under `scripts/`; the workflow calls them.
This keeps the YAML thin and allows running the same build locally on the
owner's gfx1100/gfx1151 box without a GitHub runner. llamacpp-rocm inlines its
build in YAML; pulling it into scripts is the one intentional improvement.

CachyLLama is **not** a submodule. It is shallow-cloned at a pinned commit
inside the job (matches llamacpp-rocm's `git clone --depth 1`). The pin lives
in workflow env (`CACHYLLAMA_REF`) and is bumpable per release.

## 4. Build matrix and per-job flow

Matrix: `gfx_target` × `backend`, Ubuntu only. `fail-fast: false` so one
broken gfx does not kill the rest.

| gfx_target | mapped HIP `GPU_TARGETS` | backends |
|---|---|---|
| gfx110X | gfx1100;gfx1101;gfx1102;gfx1103 | rocm, vulkan |
| gfx1150 | gfx1150 | rocm, vulkan |
| gfx1151 | gfx1151 | rocm, vulkan |
| gfx120X | gfx1200;gfx1201 | rocm, vulkan |
| gfx103X | gfx1030;gfx1031;gfx1032;gfx1034 | rocm, vulkan |
| gfx90a | gfx90a | rocm |
| gfx908 | gfx908 | rocm |

gfx90a/gfx908 are CDNA (MI-class); Vulkan is irrelevant there, so the Vulkan
jobs are dropped for those two targets. This saves two jobs and avoids
shipping meaningless Vulkan archives.

### Job graph

1. **`prepare-matrix`** (`ubuntu-22.04`) — parses `workflow_dispatch` inputs
   or defaults, emits a JSON matrix plus `should_build_*` flags. Pattern
   reused from llamacpp-rocm.

2. **`build-ubuntu`** (`ubuntu-22.04`, matrix) — one job per (gfx, backend):
   - free disk space (reuse llamacpp-rocm's `util_free_space.sh` curl)
   - install `cmake ninja-build unzip curl zstd patchelf`
   - **ROCm jobs only:** stream TheRock SDK to `/opt/rocm`, set ROCm env
     vars (`HIP_PATH`, `ROCM_PATH`, `HIP_CLANG_PATH`, `LD_LIBRARY_PATH`,
     `PATH`, etc.)
   - shallow-clone CachyLLama at `CACHYLLAMA_REF`
   - run `scripts/build-rocm.sh` **or** `scripts/build-vulkan.sh`
   - **ROCm only:** `scripts/bundle-rocm-libs.sh` (copy libs + `patchelf
     --set-rpath '$ORIGIN'`)
   - smoke checks (see §6): `llama-server --version` and `ldd` gate
   - `scripts/make-archive.sh` →
     `cachy-${TAG}-ubuntu-${backend}-${gfx}-x64.tar.zst`
   - `actions/upload-artifact@v4`

3. **`create-release`** (`ubuntu-22.04`, `permissions: contents: write`) —
   downloads all artifacts, creates `tar.zst` archives, `gh release create`.
   Nightly → sequential `b####` tag (prerelease); git tag `v*` → uses that
   tag (latest/stable).

### ROCm build flags

Match the proven llamacpp-rocm CI recipe against TheRock nightlies:

```
cmake .. -G Ninja \
  -DCMAKE_C_COMPILER=/opt/rocm/llvm/bin/clang \
  -DCMAKE_CXX_COMPILER=/opt/rocm/llvm/bin/clang++ \
  -DCMAKE_CXX_FLAGS="-I/opt/rocm/include" \
  -DCMAKE_BUILD_TYPE=Release \
  -DGPU_TARGETS="<mapped>" \
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
```

CachyLLama's own `build_rocm` uses `CMAKE_HIP_ARCHITECTURES` +
`GGML_HIPBLAS=ON`; llamacpp-rocm uses `GPU_TARGETS` + `GGML_HIP=ON` (no
separate HIPBLAS flag). Both are valid llama.cpp ROCm conventions. This
pipeline uses llamacpp-rocm's flag set because it is the proven CI recipe
against TheRock nightlies, and CachyLLama tracks upstream closely enough that
the flags carry over.

### Vulkan build flags

From llama-ai `rebuild.sh` Vulkan path:

```
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
```

No ROCm SDK, no lib bundling — Vulkan loaders come from the host/driver at
runtime. Lighter archive (tens of MB vs ROCm's hundreds).

### ROCm lib bundling

`scripts/bundle-rocm-libs.sh` copies the same runtime lib set llamacpp-rocm
ships: `libhipblas`, `librocblas`, `libamdhip64`, `librocsolver`,
`libroctx64`, `libhipblaslt`, the `rocm_sysdeps_*` set, `libamd_comgr`,
`libamd_comgr_loader`, `libhsa-runtime64`, `librocroller`, `librocm_kpack`,
`libLLVM`, `libclang-cpp`, plus the `rocblas/library` and
`hipblaslt/library` kernel dirs. Then `patchelf --set-rpath '$ORIGIN'` on
every `.so*` and `llama-*` binary so the bundle is self-contained.

## 5. Release and versioning

Two release streams:

- **Nightly:** `schedule: cron` off-peak (`17 7 * * *` UTC, ~07:17). Sequential
  tag `b####` (b1001, b1002…), auto-incremented by scanning existing `b####`
  tags via `gh release list`. Marked prerelease. Same logic as llamacpp-rocm
  `create-release`.
- **Tagged:** push `v*` (e.g. `v1.0.0`) → workflow runs; release uses that
  exact tag, marked latest/stable. `CACHYLLAMA_REF` is pinned to a CachyLLama
  commit in the same tag commit so releases are reproducible.

`workflow_dispatch` inputs override defaults: `gfx_target` (comma list),
`backend` (`rocm` | `vulkan` | `both`), `create_release` (bool),
`cachyllama_ref` (override pin). Defaults build the full matrix.

### Archive naming

`cachy-${TAG}-ubuntu-${backend}-${gfx}-x64.tar.zst`

Examples:
- `cachy-b1042-ubuntu-rocm-gfx1151-x64.tar.zst`
- `cachy-v1.0.0-ubuntu-vulkan-gfx110X-x64.tar.zst`

### Release notes (generated)

Build number, OS, gfx target(s), backend(s), ROCm version (parsed from the
TheRock filename), CachyLLama commit hash, build date. Same fields as
llamacpp-rocm with `backend` added.

### Permissions and secrets

`contents: write` on the release job. `GH_TOKEN` (or default
`GITHUB_TOKEN`) for `gh release create`. No other secrets — TheRock SDK is
public, no auth required.

### Retention

Build artifacts retained 30 days (matches upstream). Release archives are
permanent on the release.

### CI cost

7 gfx × 2 backends − 2 (CDNA Vulkan dropped) = **12 jobs per nightly**,
~25–40 min each on hosted `ubuntu-22.04`. Tagged builds run only on demand.

## 6. Testing and verification

No GPU on hosted runners — inference cannot be smoke-tested. Two cheap
in-job checks instead, run inside `build-ubuntu` before upload-artifact,
gated `if: always()` so a failed check still uploads the artifact for
inspection but fails the job:

1. **Binary runs:** `./llama-server --version` (and `--help`) exits 0.
   Catches missing libs / wrong RPATH / broken linkage without a GPU.
2. **Link check:** `ldd llama-server` shows no `not found` lines. Catches a
   missing ROCm lib that `--version` lazy-loads and would not surface.

### test.yml (separate workflow)

Manual (`workflow_dispatch`) + post-release trigger. Inputs: `gfx_target`,
`backend`, `release_tag`. Downloads the named released archive, extracts it,
runs `llama-server --version`. Verifies the *released* artifact (not the
in-job build). Independent of `build.yml`.

### Out of scope

No inference benchmark, no model load, no GPU smoke. A self-hosted GPU
runner is explicitly out of scope (declined). Real GPU validation happens on
the owner's gfx1100/gfx1151 box by running the downloaded archive;
`docs/build.md` documents that manual step.

## 7. Documentation

### README.md

Mirrors llamacpp-rocm structure:
- Header badges (release, ROCm 7, llama.cpp/CachyLLama, OS=Ubuntu, gfx list)
- What it is: CachyLLama built with ROCm 7 for lemonade
- Supported devices table (gfx → archive name)
- Download + extract + run (copy llamacpp-rocm's 3-step flow)
- Automated builds section (nightly + tags + manual)
- Build-from-source pointer to `docs/build.md`
- Credit: CachyLLama, TheRock, llamacpp-rocm recipe

### docs/build.md

For reproducing locally on a real GPU:
- Prerequisites (cmake, ninja, TheRock SDK or system ROCm)
- `scripts/build-rocm.sh` / `build-vulkan.sh` env vars (`CACHYLLAMA_REF`,
  `GFX_TARGET`, `ROCM_PATH`)
- Manual GPU validation step (`llama-server -m model.gguf` on gfx1100/gfx1151)
- How to add a gfx target (matrix map + HIP `GPU_TARGETS` mapping)
- How to cut a release (`git tag v1.0.0 && git push --tags`; pin
  `CACHYLLAMA_REF`)

### .gitignore

`llama.cpp/`, `build/`, `*.tar.zst`, `*.tar.gz`, local `/opt/rocm` scratch.

### Not included

No `CLAUDE.md` / `AGENTS.md` in this repo — it is a build pipeline, not a
codebase. Add one only if the repo grows logic worth guiding.

## 8. Open / deferred

- **test.yml:** included in v1 (per owner decision).
- **Nightly matrix trimming:** not applied; full matrix nightly. Can trim to
  owner's gfx110X + gfx1151 nightly and run the full matrix only on tags if
  CI minutes become a concern.
- **Windows targets:** not in v1; Ubuntu only. Add later via a
  `build-windows` job mirroring llamacpp-rocm if lemonade runs on Windows.