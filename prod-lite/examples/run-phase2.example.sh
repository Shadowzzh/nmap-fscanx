#!/usr/bin/env bash

set -euo pipefail

nmap-fscanx phase2 \
  --scan-root "$HOME/.local/share/nmap-fscanx/scans/demo-all"
