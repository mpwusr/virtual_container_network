Allow ICMP between the two VM internal IPs (for ping tests)

Allow UDP overlay port between the two VM internal IPs (default below uses 9000/udp)

Minimal ingress rule:

Direction: Ingress

Targets: your two instances (tags recommended)

Source: VPC CIDR (or just the other VM internal IP)

Protocols: icmp, udp:9000

Additional notes:
- Ensure that the firewall rules are applied to the correct network and subnet.
- Verify that the instances have the appropriate tags for targeting.
- Consider using a more specific source IP range if possible for security.