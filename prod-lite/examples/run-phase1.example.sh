#!/usr/bin/env bash

set -euo pipefail

nmap-fscanx phase1 \
  --targets '192.168.1.0/24,192.168.20.0/24' \
  --scan-root "./scans/demo-phase1"
