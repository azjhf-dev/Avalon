# Building Avalon on the two target GPUs

Both recipes end with the same run command; see the upstream README for the
full flag list, or just use the `avalon-server` launcher (installed by
`install.sh` on ROCm, or by the
[avalon-performance-setup](https://github.com/azjhf-dev/avalon-performance-setup)
wizard on NVIDIA).

## NVIDIA Blackwell (RTX 50 series, sm_120)

**Untested on hardware.** Upstream Avalon tested CUDA on a rented RTX 4090
(sm_89, CUDA 12.4); the community Windows build reports RTX 5070 Ti working.
Blackwell needs CUDA 12.8+ (CUDA 13 recommended) — older toolkits don't know
sm_120.

```bash
git clone https://github.com/azjhf-dev/Avalon && cd Avalon
cmake --preset cuda-sm120        # added on this branch; or by hand:
cmake -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=120 -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)" --target llama-server
```

Then download the model (~89 GiB) and run:

```bash
hf download freriadoc/Qwen3.8-Flash-Next-Avalon-GGUF --local-dir Qwen3.8-Flash-Next-Avalon-GGUF
```

On NVIDIA, backend sampling is on by default (~6% faster per step on the
4090 measurement). Two Blackwell cards run as Avalon's default 2-stage
pipeline; >2 GPUs is untested upstream (see fixes/README.md, fix 1).

## AMD RDNA3 (RX 7900 XT/XTX, gfx1100)

This is upstream's tuned target. The ROCm installer does everything
(machine check, build, model download, launcher):

```bash
curl -fsSL https://raw.githubusercontent.com/freriadoc/Avalon/main/install.sh | bash
```

By hand (ROCm 7.x):

```bash
git clone https://github.com/azjhf-dev/Avalon && cd Avalon
cmake --preset rocm-gfx1100      # added on this branch; or by hand:
cmake -B build -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1100 -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=/opt/rocm/bin/amdclang -DCMAKE_CXX_COMPILER=/opt/rocm/bin/amdclang++
cmake --build build -j"$(nproc)" --target llama-server
```

Upstream numbers on a 7900 XT (PCIe 3.0, DDR4-3200): ~98 tok/s decode with
MTP on a short prompt, ~81 tok/s at 250k context filled. Two AMD GPUs and
the chunked-prompt GDN kernel beyond RDNA3 are untested upstream.
