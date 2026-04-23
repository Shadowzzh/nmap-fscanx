#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
用法：
  discover_targets.sh [输出目录]

说明：
  自动发现当前主机可扫描的 IPv4 候选网段，
  输出 `targets.txt` 和 `targets.meta.json`。

支持平台：
  macOS：`ifconfig` + `netstat -rn -f inet`
  Linux：`ip -4 addr show` + `ip -4 route show`

保留范围：
  `10.0.0.0/8` `172.16.0.0/12` `192.168.0.0/16` `100.64.0.0/10`

过滤规则：
  排除 `127.0.0.0/8` `169.254.0.0/16` `224.0.0.0/4` 和 `/32`

测试环境变量：
  `DISCOVER_IFCONFIG_FILE` `DISCOVER_NETSTAT_FILE`
  `DISCOVER_IP_ADDR_FILE` `DISCOVER_IP_ROUTE_FILE`

计算方式：
  1. 从活动网卡读取 IPv4 和掩码，换算成 CIDR
  2. 从 IPv4 路由表读取可达网段，统一转成 CIDR
  3. 过滤、去重、合并后写入 `targets.txt`
  4. 将来源和标记信息写入 `targets.meta.json`
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 1 ]]; then
  usage >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

output_dir="${1:-.}"
targets_path="${output_dir}/targets.txt"
meta_path="${output_dir}/targets.meta.json"

mkdir -p "$output_dir"

python3 - "$targets_path" "$meta_path" "${DISCOVER_IFCONFIG_FILE:-}" "${DISCOVER_NETSTAT_FILE:-}" "${DISCOVER_IP_ADDR_FILE:-}" "${DISCOVER_IP_ROUTE_FILE:-}" <<'PY'
import datetime
import ipaddress
import json
import pathlib
import platform
import re
import shutil
import subprocess
import sys


TARGETS_PATH = pathlib.Path(sys.argv[1])
META_PATH = pathlib.Path(sys.argv[2])
IFCONFIG_OVERRIDE = sys.argv[3]
NETSTAT_OVERRIDE = sys.argv[4]
IP_ADDR_OVERRIDE = sys.argv[5]
IP_ROUTE_OVERRIDE = sys.argv[6]

PRIVATE_CANDIDATES = (
    ipaddress.IPv4Network("10.0.0.0/8"),
    ipaddress.IPv4Network("172.16.0.0/12"),
    ipaddress.IPv4Network("192.168.0.0/16"),
    ipaddress.IPv4Network("100.64.0.0/10"),
)

EXCLUDED_CANDIDATES = (
    ipaddress.IPv4Network("127.0.0.0/8"),
    ipaddress.IPv4Network("169.254.0.0/16"),
    ipaddress.IPv4Network("224.0.0.0/4"),
)


def read_text(command, override_path):
    if override_path:
        return pathlib.Path(override_path).read_text(encoding="utf-8")
    return subprocess.check_output(command, text=True)


def is_vpn_interface(interface_name):
    return interface_name.startswith(("utun", "tun", "tap", "ppp", "ipsec", "wg", "tailscale"))


def is_candidate_network(network):
    return any(network.subnet_of(candidate) for candidate in PRIVATE_CANDIDATES)


def is_excluded_network(network):
    if network.prefixlen == 32:
        return True
    return any(network.subnet_of(candidate) for candidate in EXCLUDED_CANDIDATES)


def normalize_destination(destination):
    if destination == "default":
        return None

    if "/" in destination:
        address_text, prefix_text = destination.split("/", 1)
        octets = address_text.split(".")
        if not all(part.isdigit() for part in octets):
            return None
        padded = octets + ["0"] * (4 - len(octets))
        if len(padded) != 4:
            return None
        try:
            return ipaddress.IPv4Network((".".join(padded), int(prefix_text)), strict=False)
        except ValueError:
            return None

    if not re.fullmatch(r"\d+(?:\.\d+){0,3}", destination):
        return None

    octets = destination.split(".")
    padded = octets + ["0"] * (4 - len(octets))
    try:
        return ipaddress.IPv4Network((".".join(padded), len(octets) * 8), strict=False)
    except ValueError:
        return None


def command_exists(name):
    return shutil.which(name) is not None


def choose_discovery_mode():
    if IFCONFIG_OVERRIDE or NETSTAT_OVERRIDE:
        return "macos"

    if IP_ADDR_OVERRIDE or IP_ROUTE_OVERRIDE:
        return "linux"

    system_name = platform.system()
    if system_name == "Darwin":
        if command_exists("ifconfig") and command_exists("netstat"):
            return "macos"
        if command_exists("ip"):
            return "linux"
    elif system_name == "Linux":
        if command_exists("ip"):
            return "linux"

    if command_exists("ifconfig") and command_exists("netstat"):
        return "macos"

    if command_exists("ip"):
        return "linux"

    raise RuntimeError("Unable to find supported network discovery commands")


records = {}


def ensure_record(network):
    cidr = str(network)
    if cidr not in records:
        records[cidr] = {
            "cidr": cidr,
            "sources": [],
            "interfaces": [],
            "is_vpn": False,
            "requires_manual_confirmation": network.prefixlen < 20,
            "route_type": "route",
        }
    return records[cidr]


def add_record(network, source, interface_name):
    if not is_candidate_network(network):
        return
    if is_excluded_network(network):
        return

    record = ensure_record(network)
    if source not in record["sources"]:
        record["sources"].append(source)
    if interface_name and interface_name not in record["interfaces"]:
        record["interfaces"].append(interface_name)

    if source == "interface":
        record["route_type"] = "direct"

    if interface_name and is_vpn_interface(interface_name):
        record["is_vpn"] = True
        record["route_type"] = "vpn"


def collect_from_ifconfig(text):
    blocks = re.split(r"(?m)^(?=\S)", text)
    for block in blocks:
        if not block.strip():
            continue
        lines = block.splitlines()
        interface_name = lines[0].split(":", 1)[0]
        if "status: active" not in block:
            continue

        for match in re.finditer(r"inet (\d+\.\d+\.\d+\.\d+) netmask (0x[0-9a-fA-F]+)", block):
            address = match.group(1)
            netmask = str(ipaddress.IPv4Address(int(match.group(2), 16)))
            network = ipaddress.IPv4Network((address, netmask), strict=False)
            add_record(network, "interface", interface_name)


def collect_from_netstat(text):
    in_table = False
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("Destination"):
            in_table = True
            continue
        if not in_table:
            continue

        fields = raw_line.split()
        if len(fields) < 4:
            continue

        destination = fields[0]
        interface_name = fields[3]

        network = normalize_destination(destination)
        if network is None:
            continue

        add_record(network, "route", interface_name)


def collect_from_ip_addr(text):
    current_interface = None
    current_is_active = False

    for raw_line in text.splitlines():
        header_match = re.match(r"^\d+:\s+([^:]+):\s+<([^>]*)>", raw_line)
        if header_match:
            current_interface = header_match.group(1).split("@", 1)[0]
            flags = {part.strip() for part in header_match.group(2).split(",")}
            current_is_active = "UP" in flags
            continue

        if not current_interface or not current_is_active:
            continue

        address_match = re.search(r"\binet\s+(\d+\.\d+\.\d+\.\d+/\d+)\b", raw_line)
        if address_match is None:
            continue

        network = ipaddress.IPv4Interface(address_match.group(1)).network
        add_record(network, "interface", current_interface)


def collect_from_ip_route(text):
    for raw_line in text.splitlines():
        fields = raw_line.split()
        if not fields:
            continue

        destination = fields[0]
        if "dev" not in fields:
            continue

        interface_index = fields.index("dev")
        if interface_index + 1 >= len(fields):
            continue

        interface_name = fields[interface_index + 1]
        network = normalize_destination(destination)
        if network is None:
            continue

        add_record(network, "route", interface_name)


discovery_mode = choose_discovery_mode()
if discovery_mode == "macos":
    collect_from_ifconfig(read_text(["ifconfig"], IFCONFIG_OVERRIDE))
    collect_from_netstat(read_text(["netstat", "-rn", "-f", "inet"], NETSTAT_OVERRIDE))
else:
    collect_from_ip_addr(read_text(["ip", "-4", "addr", "show"], IP_ADDR_OVERRIDE))
    collect_from_ip_route(read_text(["ip", "-4", "route", "show"], IP_ROUTE_OVERRIDE))

targets = sorted(
    records.values(),
    key=lambda item: (
        int(ipaddress.IPv4Network(item["cidr"]).network_address),
        ipaddress.IPv4Network(item["cidr"]).prefixlen,
    ),
)

for item in targets:
    item["sources"].sort()
    item["interfaces"].sort()

TARGETS_PATH.write_text(
    "".join(f"{item['cidr']}\n" for item in targets),
    encoding="utf-8",
)

META_PATH.write_text(
    json.dumps(
        {
            "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "targets": targets,
        },
        indent=2,
        sort_keys=True,
    )
    + "\n",
    encoding="utf-8",
)
PY

echo "Wrote targets to ${targets_path}"
echo "Wrote metadata to ${meta_path}"
