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