#!/usr/bin/env bash
# =============================================================================
# simulate_spike.sh — Simulate CPU and disk pressure to validate alert triggers
#
# Usage:
#   ./scripts/simulate_spike.sh cpu     # spike CPU for ~30 seconds
#   ./scripts/simulate_spike.sh disk    # write a 2 GB temp file then delete it
#   ./scripts/simulate_spike.sh memory  # allocate ~500 MB via Python then release
#   ./scripts/simulate_spike.sh all     # run all three in sequence
#
# Purpose: Validate that monitor.py fires the correct alerts and recovers cleanly.
# Results are captured in reports/spike_test_YYYY-MM-DD.md automatically.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="${SCRIPT_DIR}/reports"
REPORT_FILE="${REPORT_DIR}/spike_test_$(date +%Y-%m-%d).md"
TEMP_FILE="/tmp/shm_disk_spike_$$.bin"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[simulate]${NC}  $*"; }
warn() { echo -e "${YELLOW}[simulate]${NC}  $*"; }

mkdir -p "${REPORT_DIR}"

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

# ---------------------------------------------------------------------------
append_report() {
    echo "$1" >> "${REPORT_FILE}"
}

init_report() {
    cat > "${REPORT_FILE}" <<EOF
# Spike Test — Incident Report
**Date:** $(date "+%Y-%m-%d")
**Tester:** Swapnajit Sarkar
**Purpose:** Validate that system-health-monitor alert thresholds trigger and recover correctly.

---
EOF
    info "Report → ${REPORT_FILE}"
}

# ---------------------------------------------------------------------------
spike_cpu() {
    info "Starting CPU spike (30 seconds) …"
    append_report "## CPU Spike Test"
    append_report "**Start:** $(timestamp)"
    append_report ""
    append_report "### Pre-spike baseline"
    append_report "\`\`\`"
    top -bn1 | head -5 >> "${REPORT_FILE}"
    append_report "\`\`\`"
    append_report ""

    # Spin as many yes processes as there are CPU cores
    CORES=$(nproc)
    PIDS=()
    for _ in $(seq 1 "${CORES}"); do
        yes > /dev/null &
        PIDS+=($!)
    done
    warn "Spawned ${CORES} CPU-burning processes (PIDs: ${PIDS[*]}).  Sleeping 30s …"
    sleep 30

    # Kill spike processes
    for PID in "${PIDS[@]}"; do kill "${PID}" 2>/dev/null || true; done
    info "CPU spike ended."

    append_report "### Action taken"
    append_report "Spawned \`${CORES}\` \`yes > /dev/null\` processes for 30 seconds (one per CPU core)."
    append_report ""
    append_report "### Expected alert"
    append_report "- Metric: \`cpu_percent\`"
    append_report "- Threshold: > 85% for 3 consecutive cycles"
    append_report ""
    append_report "### Post-spike baseline"
    append_report "\`\`\`"
    top -bn1 | head -5 >> "${REPORT_FILE}"
    append_report "\`\`\`"
    append_report ""
    append_report "### Outcome"
    append_report "_Fill in after reviewing alerts.log: did the alert fire? At which cycle? Did it recover?_"
    append_report ""
    append_report "---"
    append_report ""
}

# ---------------------------------------------------------------------------
spike_disk() {
    info "Starting disk spike (writing 1 GB temp file) …"
    append_report "## Disk Spike Test"
    append_report "**Start:** $(timestamp)"
    append_report ""
    append_report "### Pre-spike disk usage"
    append_report "\`\`\`"
    df -h / >> "${REPORT_FILE}"
    append_report "\`\`\`"
    append_report ""

    DISK_TOTAL=$(df / | awk 'NR==2 {print $2}')     # in 1K blocks
    DISK_FREE=$(df  / | awk 'NR==2 {print $4}')
    DISK_PCT=$(df   / | awk 'NR==2 {gsub(/%/,""); print $5}')

    warn "Current disk usage: ${DISK_PCT}%.  Writing 1 GB temp file to /tmp …"
    dd if=/dev/zero of="${TEMP_FILE}" bs=1M count=1024 status=progress 2>/dev/null || true

    append_report "### Action taken"
    append_report "Wrote a 1 GB temporary file to \`${TEMP_FILE}\` using \`dd\`."
    append_report ""
    append_report "### Post-write disk usage"
    append_report "\`\`\`"
    df -h / >> "${REPORT_FILE}"
    append_report "\`\`\`"
    append_report ""

    info "Holding for 90 seconds so monitor can capture the spike …"
    sleep 90

    rm -f "${TEMP_FILE}"
    info "Temp file removed. Disk spike ended."

    append_report "### Expected alert"
    append_report "- Metric: \`disk_percent\`"
    append_report "- Threshold: > 90% for 2 consecutive cycles"
    append_report ""
    append_report "### Post-recovery disk usage"
    append_report "\`\`\`"
    df -h / >> "${REPORT_FILE}"
    append_report "\`\`\`"
    append_report ""
    append_report "### Outcome"
    append_report "_Fill in after reviewing alerts.log._"
    append_report ""
    append_report "---"
    append_report ""
}

# ---------------------------------------------------------------------------
spike_memory() {
    info "Starting memory spike (allocating ~500 MB for 60 seconds) …"
    append_report "## Memory Spike Test"
    append_report "**Start:** $(timestamp)"
    append_report ""
    append_report "### Pre-spike memory"
    append_report "\`\`\`"
    free -h >> "${REPORT_FILE}"
    append_report "\`\`\`"
    append_report ""

    python3 -c "
import time, sys
chunk = bytearray(500 * 1024 * 1024)  # 500 MB
print('[simulate]  500 MB allocated. Holding for 60 seconds ...', flush=True)
time.sleep(60)
print('[simulate]  Releasing memory.', flush=True)
del chunk
"
    info "Memory spike ended."

    append_report "### Action taken"
    append_report "Allocated 500 MB via Python \`bytearray\` for 60 seconds then released."
    append_report ""
    append_report "### Expected alert"
    append_report "- Metric: \`memory_percent\`"
    append_report "- Threshold: > 85% for 3 consecutive cycles"
    append_report ""
    append_report "### Post-recovery memory"
    append_report "\`\`\`"
    free -h >> "${REPORT_FILE}"
    append_report "\`\`\`"
    append_report ""
    append_report "### Outcome"
    append_report "_Fill in after reviewing alerts.log._"
    append_report ""
    append_report "---"
    append_report ""
}

# ---------------------------------------------------------------------------
COMMAND="${1:-help}"
init_report

case "${COMMAND}" in
    cpu)    spike_cpu    ;;
    disk)   spike_disk   ;;
    memory) spike_memory ;;
    all)
        spike_cpu
        spike_disk
        spike_memory
        ;;
    *)
        echo ""
        echo "  Usage: ./scripts/simulate_spike.sh <cpu|disk|memory|all>"
        echo ""
        echo "  cpu     Spin yes processes to saturate CPU cores for 30 seconds"
        echo "  disk    Write a 1 GB temp file to /tmp for 90 seconds then delete"
        echo "  memory  Allocate 500 MB via Python for 60 seconds then release"
        echo "  all     Run all three in sequence"
        echo ""
        exit 0
        ;;
esac

append_report "## Summary"
append_report "**End:** $(timestamp)"
append_report ""
append_report "Check \`logs/alerts.log\` to verify each alert fired and recovered correctly."
append_report "Update the Outcome section for each test above."

info "Spike test complete. Report saved to:"
info "  ${REPORT_FILE}"
