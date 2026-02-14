Create two Debian 13 VMs on the same VPC/subnet

Add firewall rule: allow icmp and udp:9000 between them

On both VMs: run sudo ./gcp-debian13-prereqs.sh

On both VMs: run sudo ./part1-bridged-network.gcp.sh (local-only learning)

On both VMs: run sudo ./part2-overlay-network.gcp.sh with SIDE and PEER_NODE_IP set

Additional notes:
- Ensure that the VMs are created in the same VPC and subnet for proper communication.
- Verify that the firewall rules are correctly configured to allow ICMP and UDP traffic on port 9000.
- Confirm that the prerequisites script (gcp-debian13-prereqs.sh) is executed successfully on both VMs.
- Check that the overlay network scripts (part2-overlay-network.gcp.sh) are executed with the correct environment variables set.
```bash
sudo ./gcp-debian13-prereqs.sh
export PEER_NODE_IP=<VM-B internal IP>
export SIDE=0
export UDP_PORT=9000
sudo ./part2-overlay-network.gcp.sh

sudo ./gcp-debian13-prereqs.sh
export PEER_NODE_IP=<VM-A internal IP>
export SIDE=1
export UDP_PORT=9000
sudo ./part2-overlay-network.gcp.sh

# Verify that the overlay network is functional by pinging between VMs
ping -c 4 <VM-B internal IP>
ping -c 4 <VM-A internal IP>
```