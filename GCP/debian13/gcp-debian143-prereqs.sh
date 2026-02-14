#!/usr/bin/env bash
set -euo pipefail

echo "=== GCP Debian 13 prereqs for container networking demos ==="

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "ERROR: run on Linux"
  exit 1
fi
if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run as root: sudo ./gcp-debian13-prereqs.sh"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "[1/5] Installing packages"
apt-get update -y
apt-get install -y \
  iproute2 \
  iputils-ping \
  socat \
  tcpdump \
  ethtool \
  curl

echo "[2/5] Loading kernel modules (best effort)"
modprobe bridge 2>/dev/null || true
modprobe veth   2>/dev/null || true
modprobe tun    2>/dev/null || true

echo "[3/5] Enable IPv4 forwarding (required)"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

echo "[4/5] Basic sanity checks"
ip -V
command -v socat >/dev/null
ip netns list || true

echo "[5/5] Done"
echo "Next: run ./part1-bridged-network.gcp.sh (local only) then ./part2-overlay-network.gcp.sh (two-node)."
