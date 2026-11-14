# fixes/ — rfairburn-style fix assessment for Avalon

Base: `freriadoc/Avalon` @ `1200934a7` (main, mid-Nov 2026).
Inspiration: [rfairburn/Strata-rdna3 `build/rdna3-f557b54-p4-fixes`](https://github.com/rfairburn/Strata-rdna3/tree/build/rdna3-f557b54-p4-fixes) — his fix stack on the Strata engine (4-GPU pipeline + queue-wake fixes, MTP on pipeline parallelism, mmap + prefill work), and the corresponding mainline [Niko1221/Strata](https://github.com/Niko1221/Strata) features.

**Everything here is untested on hardware.** No Blackwell or RDNA3 box was available when this branch was assembled. Nothing in this branch claims performance numbers.

## The honest headline: Avalon is a different engine

rfairburn's fixes target **Strata**, a standalone C++ engine (`src/core/`, `src/prefill/`, ROCr KFD queue management). Avalon is a **fork of llama.cpp**. None of his diffs apply as code — the files, allocators, schedulers, and multi-GPU architecture are unrelated. What follows is the per-fix assessment: what Avalon already has, what was portable, and what would need real engine work.

## Fix 1 — better multi-GPU support (his 4-GPU pipeline + queue-wake fixes)

**Status: NOT PORTED (architecturally incompatible), needs real engine work.**

- His core gain is a *data-parallel prompt planner*: prompt chunks fanned across 4 cards (`src/prefill/dp_plan.hpp`, `src/prefill/prefill.cpp`), plus ROCr KFD queue-wake fixes (`src/core/kfdq.cpp`).
- Avalon's multi-GPU is a **hardwired 2-stage layer pipeline**: `src/llama-model.cpp:1669` ("two GPUs that llama_context will run as pipeline stages") and the stage plumbing in `src/llama-context.cpp`. Extending it past 2 GPUs is surgery in llama-context/llama-model, not a patch that can be carried over. Avalon's own README says >2 GPUs is untested.
- His KFD queue-wake work is AMD-kernel-driver specific (Strata parks/wakes ROCr hardware queues to cut idle power). llama.cpp has no KFD layer — there is literally no file to carry it to. Host-side GPU idle/perf tuning for both vendors lives in the companion repo [azjhf-dev/avalon-performance-setup](https://github.com/azjhf-dev/avalon-performance-setup) instead.
- Note upstream llama.cpp's generic `-ts/--split-mode` layer split already supports N GPUs; what it lacks is Avalon's expert-cache awareness across >2 stages.

## Fix 2 — MTP on pipelined parallelism (from mainline Strata)

**Status: ALREADY IN AVALON — nothing to port.**

Avalon runs its MTP draft head with the 2-stage pipeline out of the box ("MTP works as with one GPU: the draft takes the target's rows chunk by chunk on the device" — upstream README), and the shipped launcher preset enables it (`--spec-type draft-mtp --spec-draft-n-max 2`). rfairburn was back-filling this into the rdna3 fork from mainline Strata; Avalon's llama.cpp base has speculative decoding with its own pipeline integration.

## Fix 3 — mmap support with improved prefill speed

**Status: PARTIALLY APPLIED (host-side only), engine side deliberately N/A.**

- Avalon **deliberately does not mmap the expert weights**: it reads them once with `O_DIRECT` into its own registered RAM arena, because page-cache eviction by other programs caused mid-token stalls. Re-adding mmap for experts would be a regression, not a fix. (Dense weights still go through llama.cpp's normal mmap path; `--no-mmap` exists if wanted.)
- The one portable piece of his mmap work is the **glibc allocator workaround** for large-allocation inference workloads: `MALLOC_MMAP_THRESHOLD_=131072` plus arena discipline, which stops glibc from pathologically mmap/munmap-ing big buffers. Ported as [`fixes/avalon-mmap-launcher.sh`](avalon-mmap-launcher.sh), an experimental wrapper around `avalon-server`.

## Related small finding — sampling defaults

rfairburn's stack also sets `presence_penalty 0` as the Qwen3.8-Flash-Next model-card default (Strata shipped 1.5 with thinking off). **N/A here:** llama.cpp's server defaults `presence_penalty` to `0.0` already (`tools/server/README.md`).

## What IS on this branch

| File | What |
| --- | --- |
| `fixes/README.md` | This assessment, with provenance |
| `fixes/avalon-mmap-launcher.sh` | Experimental: glibc allocator workaround wrapper (fix 3) |
| `fixes/BUILD.md` | Build recipes for the user's two targets: NVIDIA Blackwell (sm_120, CUDA 12.8+/13) and AMD RDNA3 (gfx1100, ROCm 7.x) |
| `CMakePresets.json` | Two additive configure presets: `cuda-sm120`, `rocm-gfx1100` |
| `BRANCHES.md` (repo root) | rfairburn-style running history of the branches being run |

Provenance: fix analysis from rfairburn/Strata-rdna3 branch `build/rdna3-f557b54-p4-fixes` (commit `b7c5a26` and its stack) and mainline Niko1221/Strata, both MIT. Avalon and llama.cpp are MIT.
