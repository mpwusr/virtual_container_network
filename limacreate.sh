#!/usr/bin/env bash
set -euo pipefail

# ---- Required: set PEER_NODE_IP to the OTHER VM's IP ----
PEER_NODE_IP="${PEER_NODE_IP:?Set PEER_NODE_IP to the other node IP}"

# ---- Required: SIDE=0 for node1, SIDE=1 for node2 ----
SIDE="${SIDE:-0}"

# ---- auto-detect local node IP + egress interface (replaces eth0) ----
NODE_IP="$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')"
NODE_DEV="$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')"

NS1="NS1"
NS2="NS2"

cleanup() {
  set +e
  sudo ip netns del "$NS1" 2>/dev/null
  sudo ip netns del "$NS2" 2>/dev/null
  sudo ip link del br0 2>/dev/null
  sudo ip link del veth10 2>/dev/null
  sudo ip link del veth20 2>/dev/null
}
trap cleanup EXIT

if [[ "$SIDE" == "0" ]]; then
  BRIDGE_IP="172.16.0.1"
  IP1="172.16.0.2"
  IP2="172.16.0.3"
  TO_BRIDGE_SUBNET="172.16.1.0/24"
  TO_BRIDGE_IP="172.16.1.1"
  TO_IP1="172.16.1.2"
  TO_IP2="172.16.1.3"
else
  BRIDGE_IP="172.16.1.1"
  IP1="172.16.1.2"
  IP2="172.16.1.3"
  TO_BRIDGE_SUBNET="172.16.0.0/24"
  TO_BRIDGE_IP="172.16.0.1"
  TO_IP1="172.16.0.2"
  TO_IP2="172.16.0.3"
fi

echo "NODE_IP=$NODE_IP NODE_DEV=$NODE_DEV PEER_NODE_IP=$PEER_NODE_IP SIDE=$SIDE"

echo "Creating namespaces"
sudo ip netns add "$NS1"
sudo ip netns add "$NS2"
sudo ip netns show

echo "Creating veth pairs"
sudo ip link add veth10 type veth peer name veth11
sudo ip link add veth20 type veth peer name veth21

echo "Moving veth peers into namespaces"
sudo ip link set veth11 netns "$NS1"
sudo ip link set veth21 netns "$NS2"

echo "Assigning IPs in namespaces"
sudo ip netns exec "$NS1" ip addr add "$IP1/24" dev veth11
sudo ip netns exec "$NS2" ip addr add "$IP2/24" dev veth21

echo "Bring up ns interfaces + loopback"
sudo ip netns exec "$NS1" ip link set lo up
sudo ip netns exec "$NS2" ip link set lo up
sudo ip netns exec "$NS1" ip link set veth11 up
sudo ip netns exec "$NS2" ip link set veth21 up

echo "Creating bridge br0"
sudo ip link add br0 type bridge
sudo ip addr add "$BRIDGE_IP/24" dev br0
sudo ip link set br0 up

echo "Attach veths to bridge and bring up"
sudo ip link set veth10 master br0
sudo ip link set veth20 master br0
sudo ip link set veth10 up
sudo ip link set veth20 up

echo "Default routes inside namespaces via bridge"
sudo ip netns exec "$NS1" ip route add default via "$BRIDGE_IP" dev veth11
sudo ip netns exec "$NS2" ip route add default via "$BRIDGE_IP" dev veth21

echo "Enable IP forwarding"
sudo sysctl -w net.ipv4.ip_forward=1

echo "Route to reach remote bridge subnet via peer node (replaces: dev eth0) "
sudo ip route add "$TO_BRIDGE_SUBNET" via "$PEER_NODE_IP" dev "$NODE_DEV" 2>/dev/null || true

echo "----- Tests (local) -----"
sudo ip netns exec "$NS1" ping -W 1 -c 2 "$IP1"
sudo ip netns exec "$NS1" ping -W 1 -c 2 "$BRIDGE_IP"
sudo ip netns exec "$NS1" ping -W 1 -c 2 "$IP2"

echo "----- Tests (cross-node) -----"
sudo ip netns exec "$NS1" ping -W 1 -c 2 "$PEER_NODE_IP"
sudo ip netns exec "$NS1" ping -W 1 -c 2 "$TO_BRIDGE_IP"
sudo ip netns exec "$NS1" ping -W 1 -c 2 "$TO_IP1"
sudo ip netns exec "$NS1" ping -W 1 -c 2 "$TO_IP2"

echo "Done."
