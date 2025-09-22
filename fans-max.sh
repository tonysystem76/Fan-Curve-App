#!/usr/bin/env bash
set -euo pipefail
busctl --system call com.system76.PowerDaemon /com/system76/PowerDaemon/Fan com.system76.PowerDaemon.Fan FullSpeed
