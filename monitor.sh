#!/usr/bin/env bash
# =============================================================================
# monitor.sh — Bash wrapper for the System Health Monitor
#
# Commands:
#   start     Start the monitor as a background process (via systemctl if
#             the service is installed, otherwise directly)
#   stop      Stop the running monitor
#   status    Show whether the monitor is running + last 5 metric lines
#   tail      Tail the live metrics log (Ctrl+C to exit)
#   alerts    Tail the live alerts log
#   restart   Stop then start
#   install   Install as a systemd user service (Ubuntu/Debian)
#   uninstall Remove the systemd service
#
# Usage:
#   chmod +x monitor.sh
#   ./monitor.sh start
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — edit these paths if your layout differs
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
MONITOR_PY="${SCRIPT_DIR}/monitor.py"
LOGDIR="${SCRIPT_DIR}/logs"
PIDFILE="${SCRIPT_DIR}/monitor.pid"
METRICS_LOG="${LOGDIR}/metrics.log"
ALERTS_LOG="${LOGDIR}/alerts.log"
SERVICE_NAME="system-health-monitor"
SERVICE_FILE="${HOME}/.config/systemd/user/${SERVICE_NAME}.service"

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[monitor]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[monitor]${NC}  $*"; }
error()   { echo -e "${RED}[monitor]${NC}  $*" >&2; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
is_running() {
    [[ -f "${PIDFILE}" ]] && kill -0 "$(cat "${PIDFILE}")" 2>/dev/null
}

require_running() {
    if ! is_running; then
        error "Monitor is not running."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
cmd_start() {
    if is_running; then
        warn "Monitor is already running (PID $(cat "${PIDFILE}"))."
        return
    fi

    # Prefer systemctl if the service is installed
    if systemctl --user is-enabled "${SERVICE_NAME}" &>/dev/null; then
        info "Starting via systemd …"
        systemctl --user start "${SERVICE_NAME}"
        info "Started.  Use './monitor.sh status' to verify."
        return
    fi

    mkdir -p "${LOGDIR}"
    nohup "${PYTHON_BIN}" "${MONITOR_PY}" \
        --logdir "${LOGDIR}" \
        >> "${LOGDIR}/stdout.log" 2>&1 &
    echo $! > "${PIDFILE}"
    info "Monitor started (PID $!)."
    info "Metrics → ${METRICS_LOG}"
    info "Alerts  → ${ALERTS_LOG}"
}

cmd_stop() {
    # Prefer systemctl
    if systemctl --user is-active "${SERVICE_NAME}" &>/dev/null; then
        info "Stopping via systemd …"
        systemctl --user stop "${SERVICE_NAME}"
        info "Stopped."
        return
    fi

    require_running
    PID=$(cat "${PIDFILE}")
    kill "${PID}" && rm -f "${PIDFILE}"
    info "Monitor stopped (PID ${PID})."
}

cmd_status() {
    echo ""
    if is_running; then
        PID=$(cat "${PIDFILE}")
        echo -e "  Status : ${GREEN}RUNNING${NC} (PID ${PID})"
        echo -e "  Uptime : $(ps -o etime= -p "${PID}" | tr -d ' ')"
    else
        # Check systemd as well
        if systemctl --user is-active "${SERVICE_NAME}" &>/dev/null 2>&1; then
            echo -e "  Status : ${GREEN}RUNNING${NC} (systemd)"
            systemctl --user status "${SERVICE_NAME}" --no-pager -l | tail -6
        else
            echo -e "  Status : ${RED}STOPPED${NC}"
        fi
    fi

    echo ""
    echo "  Log files:"
    [[ -f "${METRICS_LOG}" ]] && echo "    Metrics : ${METRICS_LOG} ($(wc -l < "${METRICS_LOG}") lines)"
    [[ -f "${ALERTS_LOG}"  ]] && echo "    Alerts  : ${ALERTS_LOG}  ($(wc -l < "${ALERTS_LOG}") lines)"

    if [[ -f "${METRICS_LOG}" ]]; then
        echo ""
        echo "  Last 5 metric readings:"
        tail -5 "${METRICS_LOG}" | while read -r line; do
            echo "    ${line}"
        done
    fi
    echo ""
}

cmd_tail() {
    [[ -f "${METRICS_LOG}" ]] || { error "No metrics log found at ${METRICS_LOG}"; exit 1; }
    info "Tailing metrics log (Ctrl+C to stop) …"
    tail -f "${METRICS_LOG}"
}

cmd_alerts() {
    [[ -f "${ALERTS_LOG}" ]] || { warn "No alerts log yet — no alerts have fired."; exit 0; }
    info "Tailing alerts log (Ctrl+C to stop) …"
    tail -f "${ALERTS_LOG}"
}

cmd_restart() {
    cmd_stop || true
    sleep 1
    cmd_start
}

cmd_install() {
    info "Installing systemd user service …"
    mkdir -p "$(dirname "${SERVICE_FILE}")"

    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=System Health Monitor
After=network.target

[Service]
Type=simple
ExecStart=${PYTHON_BIN} ${MONITOR_PY} --logdir ${LOGDIR}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable "${SERVICE_NAME}"
    info "Service installed: ${SERVICE_FILE}"
    info "Run './monitor.sh start' to launch."
}

cmd_uninstall() {
    warn "Removing systemd service …"
    systemctl --user stop   "${SERVICE_NAME}" 2>/dev/null || true
    systemctl --user disable "${SERVICE_NAME}" 2>/dev/null || true
    rm -f "${SERVICE_FILE}"
    systemctl --user daemon-reload
    info "Service removed."
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
COMMAND="${1:-help}"

case "${COMMAND}" in
    start)     cmd_start     ;;
    stop)      cmd_stop      ;;
    status)    cmd_status    ;;
    tail)      cmd_tail      ;;
    alerts)    cmd_alerts    ;;
    restart)   cmd_restart   ;;
    install)   cmd_install   ;;
    uninstall) cmd_uninstall ;;
    *)
        echo ""
        echo "  Usage: ./monitor.sh <command>"
        echo ""
        echo "  Commands:"
        echo "    start      Start the monitor"
        echo "    stop       Stop the monitor"
        echo "    status     Show status and last 5 readings"
        echo "    tail       Live-tail the metrics log"
        echo "    alerts     Live-tail the alerts log"
        echo "    restart    Restart the monitor"
        echo "    install    Install as a systemd user service"
        echo "    uninstall  Remove the systemd service"
        echo ""
        ;;
esac
