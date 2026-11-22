#!/usr/bin/env bash
# inkling2-kquant.sh - calibrated (imatrix) K-quants of Inkling 2 Mini, KQuant-style.
#
# Method: llama.cpp's stock imatrix flow (KQuant's GGUF half is exactly this; Nace AI's packs
# are careful applications of it, MIT-licensed docs: github.com/asher/mlx-kquant docs/imatrix.md).
# An importance matrix over a calibration corpus steers K-quant rounding toward the channels
# that matter; it costs nothing at inference. We measure KL vs the BF16 source for every tier
# and only "ship" tiers that beat their plain-quant baseline.
#
# NEEDS: a CUDA box (Ash's RTX 5090), ~160 GB free disk, ~32 GB RAM.
# Authored in the dev sandbox - NOT RUN there (no GPU). Paths are configurable via env.
#
# Usage:  bash scripts/inkling2-kquant.sh [build_dir]
# Env:    MODELS_DIR (default ./models)  CORPUS (bartowski calibration_datav5.txt, auto-fetched)
#         TIERS (default "Q4_K_M IQ3_XXS IQ3_S")  NGL (default 99)  CTX (imatrix ctx, default 512)

set -euo pipefail
BUILD="${1:-build-kquant}"
MODELS="${MODELS_DIR:-models}"
TIERS="${TIERS:-Q4_K_M IQ3_XXS IQ3_S}"
NGL="${NGL:-99}"
CTX="${CTX:-512}"
BASE="Inkling-2-Mini-BF16.gguf"
HF_REPO="ggml-org/Inkling-2-Mini-GGUF"
CORPUS="${CORPUS:-$MODELS/calibration_datav5.txt}"
CORPUS_URL="https://gist.githubusercontent.com/bartowski1182/82ae9b520227f57d79ba04add13d0d0d/raw/calibration_datav5.txt"

mkdir -p "$MODELS"

echo "== 1/6 build (imatrix, quantize, perplexity) =="
cmake -S . -B "$BUILD" -DGGML_CUDA=ON -DLLAMA_CURL=OFF -DLLAMA_USE_PREBUILT_UI=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD" -j --target llama-imatrix llama-quantize llama-perplexity

echo "== 2/6 fetch source GGUF + corpus =="
[ -f "$MODELS/$BASE" ] || hf download "$HF_REPO" "$BASE" --local-dir "$MODELS"
[ -f "$CORPUS" ] || curl -L "$CORPUS_URL" -o "$CORPUS"

echo "== 3/6 our imatrix (GPU) =="
# -ngl offloads the model; --no-warmup and -c keep the calibration pass representative.
# NOTE: first imatrix run of inkling2_loop anywhere - if the imatrix tool trips on the looped
# layers or the rel-bias path, that is a bug to fix in the fork, not to work around.
"$BUILD"/bin/llama-imatrix -m "$MODELS/$BASE" -f "$CORPUS" -o "$MODELS/inkling2.imatrix" \
    -ngl "$NGL" -c "$CTX" --no-warmup

echo "== 4/6 quantize tiers with our imatrix (+ ggml-org imatrix variants for comparison) =="
[ -f "$MODELS/imatrix.gguf" ] || hf download "$HF_REPO" imatrix.gguf --local-dir "$MODELS"
for t in $TIERS; do
    "$BUILD"/bin/llama-quantize --imatrix "$MODELS/inkling2.imatrix" \
        "$MODELS/$BASE" "$MODELS/Inkling-2-Mini-$t-kquant.gguf" "$t"
    "$BUILD"/bin/llama-quantize --imatrix "$MODELS/imatrix.gguf" \
        "$MODELS/$BASE" "$MODELS/Inkling-2-Mini-$t-ggmlorg.gguf" "$t"
done

echo "== 5/6 baselines: plain quants (no imatrix) of the same tiers =="
for t in $TIERS; do
    "$BUILD"/bin/llama-quantize "$MODELS/$BASE" "$MODELS/Inkling-2-Mini-$t-plain.gguf" "$t"
done

echo "== 6/6 KL + perplexity vs BF16 =="
# base logits once, then KL for every candidate; ppl on the same corpus slice for the table.
"$BUILD"/bin/llama-perplexity -m "$MODELS/$BASE" -f "$CORPUS" -ngl "$NGL" -c "$CTX" \
    --save-all-logits "$MODELS/kl-base.logits"
{
  echo "tier,variant,KL,PPL"
  for t in $TIERS; do
    for v in kquant ggmlorg plain; do
      f="$MODELS/Inkling-2-Mini-$t-$v.gguf"
      kl=$("$BUILD"/bin/llama-perplexity -m "$f" -f "$CORPUS" -ngl "$NGL" -c "$CTX" \
           --kl-divergence --kl-divergence-base "$MODELS/kl-base.logits" 2>&1 | grep -i 'KL' | tail -1)
      ppl=$("$BUILD"/bin/llama-perplexity -m "$f" -f "$CORPUS" -ngl "$NGL" -c "$CTX" 2>&1 | grep -i 'estimate' | tail -1)
      echo "$t,$v,\"$kl\",\"$ppl\""
    done
  done
} | tee "$MODELS/inkling2-kquant-results.csv"

echo "Done. Ship rule (KQuant): a tier ships only if its kquant KL < its plain KL."
