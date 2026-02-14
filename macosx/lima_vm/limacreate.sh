#!/usr/bin/env bash
set -euo pipefail

NODE1="${NODE1:-node1}"
NODE2="${NODE2:-node2}"
LIMA_NET="${LIMA_NET:-lima:shared}"

echo "[0] Host check (macOS): use ifconfig/ipconfig, not 'ip'"
echo "    Example: ipconfig getifaddr en0  (Wi-Fi) or en1, etc."
echo

echo "[1] Create VMs ($NODE1, $NODE2) on: $LIMA_NET"
limactl create --name "$NODE1" --network="$LIMA_NET"
limactl create --name "$NODE2" --network="$LIMA_NET"

echo "[2] Start VMs"
limactl start "$NODE1"
limactl start "$NODE2"

echo "[3] Install packages inside each VM (iproute2 + ping + socat)"
for n in "$NODE1" "$NODE2"; do
  limactl shell "$n" -- bash -lc '
    set -euo pipefail
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -y
      sudo apt-get install -y iproute2 iputils-ping socat
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y iproute iputils socat
    elif command -v apk >/dev/null 2>&1; then
      sudo apk add --no-cache iproute2 iputils socat
    else
      echo "Unsupported distro: install iproute2 + ping + socat manually"
      exit 1
    fi
  '
done

echo "[4] Get VM IPs"
NODE1_IP="$(limactl shell "$NODE1" -- bash -lc "ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if(\$i==\"src\") print \$(i+1)}'")"
NODE2_IP="$(limactl shell "$NODE2" -- bash -lc "ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if(\$i==\"src\") print \$(i+1)}'")"

echo "  $NODE1 IP: $NODE1_IP"
echo "  $NODE2 IP: $NODE2_IP"
echo

cat <<EOF
Next:
1) Copy your Lima-ready demo scripts into EACH VM (part1-bridged-network.lima.sh, part2-overlay-network.lima.sh)

2) Run part1:
   limactl shell $NODE1
     export PEER_NODE_IP=$NODE2_IP
     export SIDE=0
     ./part1-bridged-network.lima.sh

   limactl shell $NODE2
     export PEER_NODE_IP=$NODE1_IP
     export SIDE=1
     ./part1-bridged-network.lima.sh

3) Run part2 overlay the same way (SIDE=0/1, PEER_NODE_IP set).
EOF
