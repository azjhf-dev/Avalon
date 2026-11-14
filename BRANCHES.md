# Branch history — what I'm running

rfairburn-style running log of the branches in this fork, newest first.
Each entry: the branch, its upstream base, what it carries, and where it ran.

## 2026-11-15 — `build/avalon-1200934-fixes`

- **Base:** `freriadoc/Avalon` main @ `1200934a7`
- **Carries:** rfairburn-style fix assessment (`fixes/README.md`); the
  portable glibc allocator workaround as an experimental launcher
  (`fixes/avalon-mmap-launcher.sh`); build recipes + CMake presets for
  NVIDIA Blackwell (`cuda-sm120`) and AMD RDNA3 (`rocm-gfx1100`)
  (`fixes/BUILD.md`, `CMakePresets.json`).
- **Deliberately not carried:** 4-GPU prompt planner (Strata architecture,
  no llama.cpp analogue — Avalon's pipeline is a hardwired 2-stage design);
  KFD queue-wake fixes (AMD driver + Strata-specific); MTP-on-pipeline
  (already in Avalon); expert mmap (Avalon bypasses mmap for experts on
  purpose).
- **Status:** untested on hardware. First target: Blackwell (RTX 50 series)
  box, then RDNA3.
