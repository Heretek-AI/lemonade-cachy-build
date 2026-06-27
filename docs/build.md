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