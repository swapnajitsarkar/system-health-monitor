# System Health Monitor & Alert Dashboard

A lightweight Python monitoring tool that tracks CPU, memory, disk utilisation, and process count on a Linux system — logging metrics to a rotating file and firing threshold-based alerts when a condition is breached for a configurable number of consecutive cycles.

Built as a hands-on TSE support project, the structure mirrors real L1/L2 monitoring workflows: metric collection, threshold alerting, incident documentation, and systemd service management.

---

## Features

- **Metrics tracked:** CPU %, memory %, disk %, process count — sampled every 60 seconds (configurable)
- **Rotating log files:** Metrics written as JSON lines; logs rotate at 5 MB with 5 backups retained
- **Consecutive-cycle alerting:** Alerts fire only after a threshold is breached for N cycles in a row — avoids noise from momentary spikes
- **Automatic recovery detection:** Counter resets and a recovery entry is logged when a metric drops back below its threshold
- **Bash service wrapper:** `monitor.sh` with `start`, `stop`, `status`, `tail`, `alerts`, and `restart` commands
- **systemd integration:** One-command install as a persistent user service
- **Spike simulation:** `simulate_spike.sh` generates CPU, disk, and memory pressure to validate alert triggers
- **Incident report:** Pre-filled spike test report showing expected vs. actual behaviour

---

## Project Structure

```
system-health-monitor/
├── monitor.py                        # Core monitoring script
├── monitor.sh                        # Bash service wrapper
├── requirements.txt
├── .gitignore
├── scripts/
│   └── simulate_spike.sh             # Spike simulation for alert validation
├── reports/
│   └── spike_test_2025-07-24.md      # Spike test incident report
└── logs/                             # Created at runtime (gitignored)
    ├── metrics.log                   # JSON-line metric snapshots
    └── alerts.log                    # Threshold breach and recovery events
```

---

## Quick Start

### 1. Install dependency

```bash
pip install psutil
# or
pip install -r requirements.txt
```

### 2. Run the monitor directly

```bash
python monitor.py
# Custom interval and log directory:
python monitor.py --interval 30 --logdir ./logs
```

Output in terminal:
```
[monitor] Starting. Logging to 'logs/' every 60s.  Press Ctrl+C to stop.
  2025-07-24 14:02:05  CPU=  12.3%  MEM=  45.1%  DISK=  61.2%  PROCS=142
  2025-07-24 14:03:05  CPU=  98.7%  MEM=  45.3%  DISK=  61.2%  PROCS=147
```

### 3. Use the Bash wrapper

```bash
chmod +x monitor.sh
./monitor.sh start    # start in background
./monitor.sh status   # show status + last 5 readings
./monitor.sh tail     # live-tail metrics log
./monitor.sh alerts   # live-tail alerts log
./monitor.sh stop     # stop the monitor
```

---

## systemd Service (Ubuntu / Debian)

Run the monitor as a persistent background service that survives reboots:

```bash
./monitor.sh install     # creates ~/.config/systemd/user/system-health-monitor.service
./monitor.sh start       # starts via systemctl
./monitor.sh status      # wraps systemctl status output
./monitor.sh uninstall   # removes the service
```

The generated service file:

```ini
[Unit]
Description=System Health Monitor
After=network.target

[Service]
Type=simple
ExecStart=python3 /path/to/monitor.py --logdir /path/to/logs
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
```

---

## Alert Thresholds

Thresholds are defined in `monitor.py` and can be edited directly:

```python
THRESHOLDS = {
    "cpu_percent":    {"limit": 85.0, "consecutive": 3},
    "memory_percent": {"limit": 85.0, "consecutive": 3},
    "disk_percent":   {"limit": 90.0, "consecutive": 2},
    "process_count":  {"limit": 300,  "consecutive": 2},
}
```

| Metric           | Default Limit | Consecutive Cycles | Meaning                              |
|------------------|---------------|--------------------|--------------------------------------|
| `cpu_percent`    | 85%           | 3                  | Alert after 3 min of sustained load  |
| `memory_percent` | 85%           | 3                  | Alert after 3 min sustained pressure |
| `disk_percent`   | 90%           | 2                  | Alert after 2 readings above 90%     |
| `process_count`  | 300           | 2                  | Alert if process count stays high    |

### Alert log format

```
2025-07-24 14:05:05  WARNING   THRESHOLD BREACHED | metric=cpu_percent  value=99.4  limit=85.0  consecutive_cycles=3
2025-07-24 14:06:05  INFO      THRESHOLD RECOVERED | metric=cpu_percent  value=11.8 (was above 85.0)
```

---

## Spike Simulation

Use `scripts/simulate_spike.sh` to validate alert triggers without needing a production system:

```bash
chmod +x scripts/simulate_spike.sh

./scripts/simulate_spike.sh cpu      # Spin yes processes for 30s
./scripts/simulate_spike.sh disk     # Write a 1 GB temp file for 90s
./scripts/simulate_spike.sh memory   # Allocate 500 MB for 60s
./scripts/simulate_spike.sh all      # Run all three
```

Each run auto-generates a Markdown incident report in `reports/` with:
- Pre/post-spike baseline readings
- Action taken
- Expected vs. actual alert behaviour
- Space to fill in outcome after reviewing `alerts.log`

See `reports/spike_test_2025-07-24.md` for a filled-in example.

---

## Log Files

### `logs/metrics.log` — JSON line format

```json
{"timestamp": "2025-07-24T14:02:05", "cpu_percent": 12.3, "memory_percent": 45.1, "memory_used_mb": 3608.0, "memory_total_mb": 8192.0, "disk_percent": 61.2, "disk_used_gb": 30.6, "disk_total_gb": 50.0, "process_count": 142}
```

JSON format makes it easy to parse with `jq`, import into a spreadsheet, or feed into a log aggregator.

### `logs/alerts.log` — Standard log format

```
2025-07-24 14:05:05  WARNING   THRESHOLD BREACHED | metric=cpu_percent  value=99.4  limit=85.0  consecutive_cycles=3
```

---

## Useful Commands

```bash
# Parse metrics log with jq
cat logs/metrics.log | jq '.cpu_percent'

# Find all breaches in alerts log
grep "BREACHED" logs/alerts.log

# Check disk usage right now
df -h /

# Check top memory-consuming processes
ps aux --sort=-%mem | head -10

# Check CPU load average
uptime
```

---

## Technologies Used

| Tool / Library | Purpose |
|----------------|---------|
| Python 3.x     | Core monitoring script |
| psutil         | Cross-platform system metrics |
| logging.handlers.RotatingFileHandler | Log rotation |
| Bash           | Service wrapper and spike simulation |
| systemd        | Background service management |

---

## Why This Project

Built to demonstrate support-engineering fundamentals:

- **Metric collection + log rotation** — mirrors how production APM tools work at the agent level
- **Consecutive-cycle alerting** — real monitoring systems don't page on a single spike; this implements that logic from scratch
- **systemd service management** — a core Linux admin skill for any TSE role
- **Incident report format** — mirrors how L1/L2 support teams document and escalate findings
