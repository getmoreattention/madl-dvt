#!/bin/bash
# ==========================================================================
# Suncheek Mesh Topology Deadlock Analysis - Batch Verification
# Runs dlockdetect on all models and summarizes results
# ==========================================================================

export PATH="/usr/bin:/home/getmoreattention/bin:$PATH"
export MWB_PATH_Z3="/home/getmoreattention/bin"

MADL_ROOT="/home/getmoreattention/madl-dvt"
ANALYSIS_DIR="$MADL_ROOT/examples/MaDL/suncheek_mesh_analysis"

cd "$MADL_ROOT"

PASS=0
FAIL=0
TOTAL=0

run_test() {
    local file="$1"
    local expected="$2"
    local desc="$3"
    TOTAL=$((TOTAL + 1))

    printf "\n━━━ [%d] %s ━━━\n" "$TOTAL" "$desc"
    printf "File: %s\n" "$(basename $file)"
    printf "Expected: %s\n" "$expected"

    OUTPUT=$(/home/getmoreattention/bin/stack-2.13 exec -- dlockdetect -v --all-sources --smt-only -f "$file" 2>&1)

    DEADLOCK_COUNT=$(echo "$OUTPUT" | grep -c '"(model"')
    HAS_NO_DEADLOCK=$(echo "$OUTPUT" | grep -c "No deadlock found")

    if [ "$expected" = "DEADLOCK" ]; then
        if [ "$DEADLOCK_COUNT" -gt 0 ]; then
            printf "Result:   ✘ DEADLOCK FOUND (%d blocked channels) — MATCHES EXPECTED\n" "$DEADLOCK_COUNT"
            PASS=$((PASS + 1))
        elif [ "$HAS_NO_DEADLOCK" -gt 0 ]; then
            printf "Result:   ✓ No deadlock — MISMATCH (expected deadlock!)\n"
            FAIL=$((FAIL + 1))
        else
            printf "Result:   ⚠ INCONCLUSIVE\n"
            FAIL=$((FAIL + 1))
        fi
    else
        if [ "$HAS_NO_DEADLOCK" -gt 0 ]; then
            printf "Result:   ✓ NO DEADLOCK — MATCHES EXPECTED\n"
            PASS=$((PASS + 1))
        elif [ "$DEADLOCK_COUNT" -gt 0 ]; then
            printf "Result:   ✘ DEADLOCK FOUND — MISMATCH (expected no deadlock!)\n"
            FAIL=$((FAIL + 1))
        else
            printf "Result:   ⚠ INCONCLUSIVE\n"
            FAIL=$((FAIL + 1))
        fi
    fi
}

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   Suncheek Mesh Topology Deadlock Analysis              ║"
echo "║   Based on Suncheek NoC Architecture Specification      ║"
echo "╚══════════════════════════════════════════════════════════╝"

run_test "$ANALYSIS_DIR/01_baseline_xy_mesh.madl"         "NO_DEADLOCK" "Baseline 2x2 XY Mesh (reference)"
run_test "$ANALYSIS_DIR/03a_parent_child_shared.madl"     "DEADLOCK"    "Parent-Child Shared VoQ (Request Channel competition)"
run_test "$ANALYSIS_DIR/03b_parent_child_separated.madl"  "NO_DEADLOCK" "Parent-Child Separated VoQ (SnpReadNoSnp_Custom fix)"
run_test "$ANALYSIS_DIR/04a_data_rx_shared.madl"          "DEADLOCK"    "Data RX Shared FIFO (WB+Response contention)"
run_test "$ANALYSIS_DIR/04b_data_rx_separated.madl"       "NO_DEADLOCK" "Data RX Separated FIFO (is_sn bit fix)"
run_test "$ANALYSIS_DIR/05_burst_wormhole.madl"           "DEADLOCK"    "DMA Burst Wormhole Deadlock (burst_lock)"

echo ""
echo "══════════════════════════════════════════════════════════"
printf "Total: %d | Pass: %d | Fail: %d\n" "$TOTAL" "$PASS" "$FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo "✓ ALL TESTS MATCH EXPECTED RESULTS"
else
    echo "✘ SOME TESTS DID NOT MATCH EXPECTED RESULTS"
fi
echo "══════════════════════════════════════════════════════════"
