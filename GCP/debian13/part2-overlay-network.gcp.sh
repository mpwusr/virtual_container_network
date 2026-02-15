#!/usr/bin/env bash
set -euo pipefail

PEER_NODE_IP="${PEER_NODE_IP:?Set PEER_NODE_IP to the other VM INTERNAL IP}"
SIDE="${SIDE:?Set SIDE=0 on VM-A and SIDE=1 on VM-B}"
UDP_PORT="${UDP_PORT:-9000}"

# Optional behavior:
# KEEP_RUNNING=1  -> keep overlay up after tests (until Ctrl+C)
KEEP_RUNNING="${KEEP_RUNNING:-0}"

NODE_IP="$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')"

# --- ensure /dev/net/tun exists ---
if [[ ! -e /dev/net/tun ]]; then
  modprobe tun 2>/dev/null || true
  mkdir -p /dev/net
  if [[ ! -e /dev/net/tun ]]; then
    mknod /dev/net/tun c 10 200
    chmod 600 /dev/net/tun
  fi
fi

# --- ensure socat exists ---
if ! command -v socat >/dev/null 2>&1; then
  echo "ERROR: socat is not installed. Run: sudo apt update && sudo apt install -y socat" >&2
  exit 2
fi

NS1="NS1"
NS2="NS2"
TUN_DEV="tundudp"

cleanup() {
  set +e
  kill "${SOCAT_RX_PID:-}" "${SOCAT_TX_PID:-}" 2>/dev/null || true
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

echo "NODE_IP=$NODE_IP PEER_NODE_IP=$PEER_NODE_IP SIDE=$SIDE UDP_PORT=$UDP_PORT KEEP_RUNNING=$KEEP_RUNNING"

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

# Create/configure tun explicitly so it always exists
ip tuntap add dev "$TUN_DEV" mode tun 2>/dev/null || true
if ! ip link show "$TUN_DEV" >/dev/null 2>&1; then
  echo "ERROR: Failed to create TUN device '$TUN_DEV'. Check /dev/net/tun and kernel tun module." >&2
  ls -l /dev/net/tun || true
  exit 3
fi

ip addr flush dev "$TUN_DEV" 2>/dev/null || true
ip addr add "$TUN_IP" dev "$TUN_DEV"
ip link set "$TUN_DEV" up

# 1) RX: UDP listen -> TUN (does NOT require peer to be up)
socat -u -T 1 \
  "UDP-RECVFROM:${UDP_PORT},bind=${NODE_IP},reuseaddr" \
  "TUN:,tun-name=${TUN_DEV},iff-no-pi" \
  >/tmp/socat-${TUN_DEV}-rx.log 2>&1 &
SOCAT_RX_PID=$!

# 2) TX: TUN -> UDP sendto peer (does NOT require peer to be up)
socat -u -T 1 \
  "TUN:,tun-name=${TUN_DEV},iff-no-pi" \
  "UDP-SENDTO:${PEER_NODE_IP}:${UDP_PORT},sourceport=${UDP_PORT},bind=${NODE_IP}" \
  >/tmp/socat-${TUN_DEV}-tx.log 2>&1 &
SOCAT_TX_PID=$!

# Small sanity delay so ss/tcpdump can see sockets
sleep 0.2

echo "Local sanity:"
ip netns exec "$NS1" ping -W 1 -c 2 "$IP2"

echo "Overlay test to remote namespace IP ($REMOTE_TEST_IP):"
set +e
ip netns exec "$NS1" ping -W 1 -c 3 "$REMOTE_TEST_IP"
PING_RC=$?
set -e

if [[ $PING_RC -ne 0 ]]; then
  echo
  echo "ERROR: Overlay ping failed."
  echo "Diagnostics:"
  echo "---- tundudp link ----"
  ip link show "$TUN_DEV" || true
  echo "---- tundudp addr ----"
  ip addr show "$TUN_DEV" || true
  echo "---- UDP sockets ----"
  ss -lunp | grep ":${UDP_PORT}" || true
  echo "---- socat rx log ----"
  tail -n 80 /tmp/socat-${TUN_DEV}-rx.log 2>/dev/null || true
  echo "---- socat tx log ----"
  tail -n 80 /tmp/socat-${TUN_DEV}-tx.log 2>/dev/null || true
  echo
  echo "Common causes:"
  echo "  1) Peer script not running (run SIDE=0 on one VM and SIDE=1 on the other)."
  echo "  2) GCP firewall/tag missing for udp:${UDP_PORT} and icmp (tag: overlay-demo)."
  echo "  3) Wrong PEER_NODE_IP (must be INTERNAL IP)."
  exit 1
fi

echo "Success."

if [[ "$KEEP_RUNNING" == "1" ]]; then
  echo "KEEP_RUNNING=1 set; leaving overlay up. Press Ctrl+C to exit and cleanup."
  while true; do sleep 3600; done
fi
