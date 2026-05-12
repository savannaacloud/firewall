# Hub-and-spoke — 4 hubs + 1 spoke, native firewall

Deploys a flat-peering hub-and-spoke topology where east-west security is
enforced by the platform's native firewall (security groups) — no NVA
instance.

```
   hub-1 ──┐
   hub-2 ──┤
            ├──► spoke
   hub-3 ──┤
   hub-4 ──┘
```

## What gets created

| Resource | Count | Notes |
|---|---|---|
| `sws_network` | 5 | spoke (10.10.0.0/24) + 4 hubs |
| `sws_vpc_peering` | 4 | each hub ↔ spoke |
| `sws_security_group` | 5 | one per network |
| `sws_security_group_rule` | 8 | hubs allow spoke→\*, spoke allows each hub→\* |

Hub CIDRs are disjoint (`10.10.1.0/24` … `10.10.4.0/24`) so the spoke's
route table can reach each hub without collision.

## Apply

```bash
export SWS_API_URL=https://savannaa.com
export SWS_API_KEY=...        # from Account > API Keys
export SWS_REGION=ng-lagos-1  # or ng-abuja-1
terraform init && terraform apply
```

## When to pick this over the NVA variant

| | Native firewall | NVA |
|---|---|---|
| Inspection | none — pure SDN policy | deep packet (whatever your firewall image supports) |
| Latency | minimal, kernel-level | hop through VM |
| Cost | $0 (SGs are free) | NVA flavor monthly cost |
| Complexity | low | medium-high |

Use native firewall when you only need L3/L4 segmentation. Use the NVA
variant (see `../hub-spoke-nva/`) when you need L7 / IDS / VPN / NAT.
