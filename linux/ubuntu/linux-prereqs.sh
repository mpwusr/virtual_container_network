#!/usr/bin/env bash
set -euo pipefail

echo "=== Linux Prerequisites for Container Networking Demos ==="

# Must run on Linux
if [[ "$(uname -s)" != "Linux" ]]; then
  echo "ERROR: This script must be run on Linux."
  exit 1
fi

# Must run as root (netns, bridges, sysctl)
if [[ "$EUID" -ne 0 ]]; then
  echo "ERROR: Please run as root (sudo ./linux-prereqs.sh)"
  exit 1
fi

echo "[1/6] Detecting Linux distribution..."
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "ERROR: Cannot detect OS (missing /etc/os-release)"
  exit 1
fi

echo "Detected OS: $NAME ($ID $VERSION_ID)"

echo "[2/6] Installing required packages..."
case "$ID" in
  ubuntu|debian)
    apt-get update -y
    apt-get install -y \
      iproute2 \
      iputils-ping \
      socat \
      bridge-utils \
      ethtool \
      tcpdump
    ;;
  rhel|centos|rocky|almalinux)
    dnf install -y \
      iproute \
      iputils \
      socat \
      bridge-utils \
      ethtool \
      tcpdump
    ;;
  fedora)
    dnf install -y \
      iproute \
      iputils \
      socat \
      bridge-utils \
      ethtool \
      tcpdump
    ;;
  arch)
    pacman -Sy --noconfirm \
      iproute2 \
      iputils \
      socat \
      bridge-utils \
      ethtool \
      tcpdump
    ;;
  *)
    echo "WARNING: Unsupported distro ($ID)."
    echo "Install manually:"
    echo "  iproute2 iputils-ping socat bridge-utils ethtool tcpdump"
    ;;
esac

echo "[3/6] Verifying kernel features..."

required_modules=(
  "bridge"
  "veth"
  "tun"
)

for mod in "${required_modules[@]}"; do
  if ! lsmod | grep -q "^${mod}"; then
    echo "Loading kernel module: $mod"
    modprobe "$mod" || echo "WARNING: Could not load $mod (may be built-in)"
  fi
done

echo "[4/6] Enabling IPv4 forwarding (required for multi-namespace routing)..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# Persist it
if ! grep -q "net.ipv4.ip_forward" /etc/sysctl.conf; then
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi

echo "[5/6] Sanity checks..."

echo "- iproute2:"
ip -V

echo "- Network namespaces:"
ip netns list || true

echo "- Bridge support:"
ip link add name br-test type bridge
ip link del br-test

echo "[6/6] Cleanup check complete."

cat <<EOF

✅ Linux prerequisites installed successfully.

You can now run:
  sudo ./part1-bridged-network.sh
  sudo ./part2-ovelay-network-1.sh
  sudo ./part3-*.sh

Notes:
- Must be run as root (netns + bridge operations)
- Assumes a single Linux host or multiple Linux nodes with L3 reachability
- If scripts reference 'eth0', verify your primary interface:
    ip -4 route get 1.1.1.1

EOF
