#!/usr/bin/env bash
set -euo pipefail

NS1="NS1"
NS2="NS2"

BRIDGE_IP="172.16.0.1"
IP1="172.16.0.2"
IP2="172.16.0.3"

cleanup() {
  set +e
  ip netns del "$NS1" 2>/dev/null
  ip netns del "$NS2" 2>/dev/null
  ip link del br0 2>/dev/null
  ip link del veth10 2>/dev/null
  ip link del veth20 2>/dev/null
}
trap cleanup EXIT

echo "Creating namespaces"
ip netns add "$NS1"
ip netns add "$NS2"

echo "Creating veth pairs"
ip link add veth10 type veth peer name veth11
ip link add veth20 type veth peer name veth21

echo "Move peers into namespaces"
ip link set veth11 netns "$NS1"
ip link set veth21 netns "$NS2"

echo "Assign IPs"
ip netns exec "$NS1" ip addr add "$IP1/24" dev veth11
ip netns exec "$NS2" ip addr add "$IP2/24" dev veth21

echo "Bring up lo + veth"
ip netns exec "$NS1" ip link set lo up
ip netns exec "$NS2" ip link set lo up
ip netns exec "$NS1" ip link set veth11 up
ip netns exec "$NS2" ip link set veth21 up

echo "Create bridge br0"
ip link add br0 type bridge
ip addr add "$BRIDGE_IP/24" dev br0
ip link set br0 up

echo "Attach veth to bridge"
ip link set veth10 master br0
ip link set veth20 master br0
ip link set veth10 up
ip link set veth20 up

echo "Default routes inside namespaces"
ip netns exec "$NS1" ip route add default via "$BRIDGE_IP"
ip netns exec "$NS2" ip route add default via "$BRIDGE_IP"

echo "Enable IP forwarding"
sysctl -w net.ipv4.ip_forward=1 >/dev/null

echo "Local tests"
ip netns exec "$NS1" ping -W 1 -c 2 "$BRIDGE_IP"
ip netns exec "$NS1" ping -W 1 -c 2 "$IP2"

cat <<'EOF'

NOTE (GCP cloud behavior):
- Cross-VM routing of 172.16.x.x directly over eth0 will NOT work due to source-IP anti-spoofing.
- Use the overlay script (part2-overlay-network.gcp.sh) for multi-node connectivity.

EOF
