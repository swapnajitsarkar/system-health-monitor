"""
System Health Monitor
---------------------
Tracks CPU, memory, disk utilisation, and process count every 60 seconds.
Writes metrics to a rotating log file and triggers threshold-based alerts
when a condition is breached for N consecutive cycles.

Usage:
    python monitor.py              # run with defaults
    python monitor.py --interval 30 --logdir ./logs
"""

import psutil
import logging
import logging.handlers
import argparse
import time
import os
import json
from datetime import datetime

# ---------------------------------------------------------------------------
# Default thresholds — all values are percentages except PROCESS_COUNT
# An alert fires when the condition holds for CONSECUTIVE_CYCLES cycles.
# ---------------------------------------------------------------------------
THRESHOLDS = {
    "cpu_percent":    {"limit": 85.0, "consecutive": 3},
    "memory_percent": {"limit": 85.0, "consecutive": 3},
    "disk_percent":   {"limit": 90.0, "consecutive": 2},
    "process_count":  {"limit": 300,  "consecutive": 2},
}

ALERT_LOG_FILE   = "alerts.log"
METRICS_LOG_FILE = "metrics.log"
LOG_MAX_BYTES    = 5 * 1024 * 1024   # 5 MB per file
LOG_BACKUP_COUNT = 5                 # keep 5 rotated files


# ---------------------------------------------------------------------------
# Logging setup
# ---------------------------------------------------------------------------

def setup_loggers(logdir: str):
    os.makedirs(logdir, exist_ok=True)

    def make_rotating_handler(filename):
        path = os.path.join(logdir, filename)
        handler = logging.handlers.RotatingFileHandler(
            path,
            maxBytes=LOG_MAX_BYTES,
            backupCount=LOG_BACKUP_COUNT,
        )
        handler.setFormatter(
            logging.Formatter("%(asctime)s  %(levelname)-8s  %(message)s",
                              datefmt="%Y-%m-%d %H:%M:%S")
        )
        return handler

    # Metrics logger — INFO and above
    metrics_logger = logging.getLogger("metrics")
    metrics_logger.setLevel(logging.INFO)
    metrics_logger.addHandler(make_rotating_handler(METRICS_LOG_FILE))

    # Alert logger — WARNING and above, also echoes to stdout
    alert_logger = logging.getLogger("alerts")
    alert_logger.setLevel(logging.WARNING)
    alert_logger.addHandler(make_rotating_handler(ALERT_LOG_FILE))

    stdout_handler = logging.StreamHandler()
    stdout_handler.setFormatter(
        logging.Formatter("%(asctime)s  [ALERT]  %(message)s",
                          datefmt="%H:%M:%S")
    )
    alert_logger.addHandler(stdout_handler)

    return metrics_logger, alert_logger


# ---------------------------------------------------------------------------
# Metric collection
# ---------------------------------------------------------------------------

def collect_metrics() -> dict:
    """Return a snapshot of current system health metrics."""
    cpu     = psutil.cpu_percent(interval=1)          # 1-second sample
    mem     = psutil.virtual_memory()
    disk    = psutil.disk_usage("/")
    procs   = len(psutil.pids())

    return {
        "timestamp":      datetime.now().isoformat(timespec="seconds"),
        "cpu_percent":    cpu,
        "memory_percent": mem.percent,
        "memory_used_mb": round(mem.used / 1024 / 1024, 1),
        "memory_total_mb":round(mem.total / 1024 / 1024, 1),
        "disk_percent":   disk.percent,
        "disk_used_gb":   round(disk.used / 1024 / 1024 / 1024, 2),
        "disk_total_gb":  round(disk.total / 1024 / 1024 / 1024, 2),
        "process_count":  procs,
    }


# ---------------------------------------------------------------------------
# Alert state tracker
# ---------------------------------------------------------------------------

class AlertTracker:
    """
    Fires an alert only after a metric exceeds its threshold for
    CONSECUTIVE_CYCLES consecutive readings.  Resets the counter when
    the metric drops back below the threshold.
    """

    def __init__(self, thresholds: dict):
        self.thresholds  = thresholds
        self._counters   = {k: 0 for k in thresholds}
        self._in_alert   = {k: False for k in thresholds}

    def check(self, metrics: dict, alert_logger):
        for key, cfg in self.thresholds.items():
            value = metrics.get(key)
            if value is None:
                continue

            limit       = cfg["limit"]
            consecutive = cfg["consecutive"]
            breached    = value > limit

            if breached:
                self._counters[key] += 1
                if self._counters[key] >= consecutive and not self._in_alert[key]:
                    self._in_alert[key] = True
                    alert_logger.warning(
                        "THRESHOLD BREACHED | metric=%-18s value=%-8.1f "
                        "limit=%-8.1f consecutive_cycles=%d",
                        key, value, limit, self._counters[key]
                    )
            else:
                if self._in_alert[key]:
                    alert_logger.info(
                        "THRESHOLD RECOVERED | metric=%-18s value=%.1f (was above %.1f)",
                        key, value, limit
                    )
                self._counters[key]  = 0
                self._in_alert[key]  = False


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

def run(interval: int, logdir: str):
    metrics_logger, alert_logger = setup_loggers(logdir)
    tracker = AlertTracker(THRESHOLDS)

    print(f"[monitor] Starting. Logging to '{logdir}/' every {interval}s.  "
          f"Press Ctrl+C to stop.")

    while True:
        try:
            snap = collect_metrics()

            # Write full metric snapshot as JSON line for easy parsing
            metrics_logger.info(json.dumps(snap))

            # Human-readable stdout summary
            print(
                f"  {snap['timestamp']}  "
                f"CPU={snap['cpu_percent']:5.1f}%  "
                f"MEM={snap['memory_percent']:5.1f}%  "
                f"DISK={snap['disk_percent']:5.1f}%  "
                f"PROCS={snap['process_count']}"
            )

            # Check thresholds and fire alerts if needed
            tracker.check(snap, alert_logger)

            time.sleep(interval)

        except KeyboardInterrupt:
            print("\n[monitor] Stopped by user.")
            break
        except Exception as exc:
            alert_logger.error("Unexpected error: %s", exc)
            time.sleep(interval)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def parse_args():
    p = argparse.ArgumentParser(description="System Health Monitor")
    p.add_argument("--interval", type=int, default=60,
                   help="Polling interval in seconds (default: 60)")
    p.add_argument("--logdir",   type=str, default="logs",
                   help="Directory for log files (default: ./logs)")
    return p.parse_args()


if __name__ == "__main__":
    args = parse_args()
    run(interval=args.interval, logdir=args.logdir)
