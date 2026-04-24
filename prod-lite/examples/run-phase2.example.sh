#!/usr/bin/env bash

set -euo pipefail

nmap-fscanx phase2 \
  --scan-root "./scans/demo-all"
