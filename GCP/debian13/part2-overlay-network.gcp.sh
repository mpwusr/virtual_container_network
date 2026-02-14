#!/usr/bin/env bash
set -euo pipefail

PEER_NODE_IP="${PEER_NODE_IP:?Set PEER_NODE_IP to the other VM INTERNAL IP}"
SIDE="${SIDE:?Set SIDE=0 on VM-A and SIDE=1 on VM-B}"
UDP_PORT="${UDP_PORT:-9000}"

NODE_IP="$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')"

NS1="NS1"
NS2="NS2"
TUN_DEV="tundudp"

cleanup() {
  set +e
  pkill -f "socat.*UDP:.*:${UDP_PORT}.*TUN:.*${TUN_DEV}" 2>/dev/null
  ip netns del "$NS1" 2>/dev/null
  ip netns del "$NS2" 2>/dev/null
  ip link del br0 2>/dev/null
  ip link del veth10 2>/dev/null
  ip link del veth20 2>/dev/null
  ip link del "$TUN_DEV" 2>/dev/null
}
trap cleanup EXIT

if [[ "$SIDE" == "0" ]]; then
  BRIDGE_IP="172.16.0.1"
  IP1="172.16.0.2"
  IP2="172.16.0.3"
  TUN_IP="172.16.0.100/16"
  REMOTE_TEST_IP="172.16.1.2"
else
  BRIDGE_IP="172.16.1.1"
  IP1="172.16.1.2"
  IP2="172.16.1.3"
  TUN_IP="172.16.1.100/16"
  REMOTE_TEST_IP="172.16.0.2"
fi

echo "NODE_IP=$NODE_IP PEER_NODE_IP=$PEER_NODE_IP SIDE=$SIDE UDP_PORT=$UDP_PORT"

# --- local bridge + namespaces ---
ip netns add "$NS1"
ip netns add "$NS2"

ip link add veth10 type veth peer name veth11
ip link add veth20 type veth peer name veth21

ip link set veth11 netns "$NS1"
ip link set veth21 netns "$NS2"

ip netns exec "$NS1" ip addr add "$IP1/24" dev veth11
ip netns exec "$NS2" ip addr add "$IP2/24" dev veth21

ip netns exec "$NS1" ip link set lo up
ip netns exec "$NS2" ip link set lo up
ip netns exec "$NS1" ip link set veth11 up
ip netns exec "$NS2" ip link set veth21 up

ip link add br0 type bridge
ip addr add "$BRIDGE_IP/24" dev br0
ip link set br0 up

ip link set veth10 master br0
ip link set veth20 master br0
ip link set veth10 up
ip link set veth20 up

ip netns exec "$NS1" ip route add default via "$BRIDGE_IP"
ip netns exec "$NS2" ip route add default via "$BRIDGE_IP"

sysctl -w net.ipv4.ip_forward=1 >/dev/null

# --- overlay: UDP <-> TUN ---
# Underlay uses NODE_IP<->PEER_NODE_IP UDP:UDP_PORT
# Inner traffic uses 172.16.x.x
socat \
  "UDP:${PEER_NODE_IP}:${UDP_PORT},bind=${NODE_IP}:${UDP_PORT}" \
  "TUN:${TUN_IP},tun-name=${TUN_DEV},iff-no-pi,tun-type=tun,iff-up" \
  >/tmp/socat-${TUN_DEV}.log 2>&1 &

sleep 1
ip link set "$TUN_DEV" up

echo "Local sanity:"
ip netns exec "$NS1" ping -W 1 -c 2 "$IP2"

echo "Overlay test to remote namespace IP ($REMOTE_TEST_IP):"
ip netns exec "$NS1" ping -W 1 -c 3 "$REMOTE_TEST_IP"

echo "Success. (If ping fails, confirm GCP firewall allows UDP:${UDP_PORT} and ICMP between VM internal IPs.)"
