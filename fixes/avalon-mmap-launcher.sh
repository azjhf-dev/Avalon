#!/usr/bin/env bash
# avalon-mmap-launcher.sh — experimental launcher wrapper for avalon-server.
#
# Provenance: ported from rfairburn's Strata-rdna3 mmap/prefill work
# (https://github.com/rfairburn/Strata-rdna3/tree/build/rdna3-f557b54-p4-fixes).
# The portable idea is his glibc allocator workaround for large-allocation
# inference workloads: stop glibc malloc from mmap/munmap-ing big buffers
# (which shows up as soft-page-fault storms and prefill jitter) by raising
# the mmap threshold and capping arena count.
#
# NOTE: this does NOT change how Avalon maps the model. Avalon reads expert
# weights once with O_DIRECT into its own RAM arena on purpose; only the
# dense-weight path uses llama.cpp's normal mmap. This wrapper only tunes
# the process allocator around that behavior.
#
# UNTESTED ON HARDWARE. Measure before/after with the benchmark in
# avalon-performance-setup before keeping it.
#
# Usage:
#   fixes/avalon-mmap-launcher.sh [extra llama-server args...]
#   (defaults to `avalon-server` on PATH; override with AVALON_SERVER=...)

set -euo pipefail

# glibc allocator workaround (rfairburn):
# - mmap threshold 128 KiB: big KV/expert-arena-adjacent allocations stay in
#   the heap instead of bouncing through mmap/munmap.
# - cap arenas at 2x CPU count upper bound 8: the server is mostly
#   single-writer; more arenas just fragment the big arena.
export MALLOC_MMAP_THRESHOLD_=131072
export MALLOC_TRIM_THRESHOLD_=131072
export MALLOC_ARENA_MAX=8

SERVER="${AVALON_SERVER:-avalon-server}"
exec "$SERVER" "$@"
