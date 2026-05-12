# Hub-and-spoke — 1 hub + 4 spokes, NVA inspection

Classic enterprise hub-and-spoke where a Network Virtual Appliance sits on
the hub and inspects all cross-spoke and north-south traffic.

```
              ┌────► spoke-1
              ├────► spoke-2
   hub ─► NVA ┤
              ├────► spoke-3
              └────► spoke-4
```

## What gets created

| Resource | Count | Notes |
|---|---|---|
| `sws_network` | 5 | hub (10.20.0.0/24) + 4 spokes |
| `sws_vpc_peering` | 4 | each spoke ↔ hub |
| `sws_instance` | 1 | the NVA |
| `sws_keypair` | 0-1 | only if `ssh_public_key` is set |
| `sws_security_group` | 5 | NVA SG + per-spoke SG |
| `sws_security_group_rule` | 9 | NVA mgmt + 4 hub-side + 4 spoke-side |

Spoke SGs pin ingress to the NVA's fixed IP (`/32`), not the whole hub
CIDR. That guarantees no future hub-side VM can bypass the appliance.

## Apply

```bash
export SWS_API_URL=https://savannaa.com
export SWS_API_KEY=...
export SWS_REGION=ng-lagos-1

terraform init
terraform apply \
  -var "ssh_public_key=$(cat ~/.ssh/id_rsa.pub)" \
  -var "nva_image_name=pfSense 2.7"   # or whichever marketplace NVA image
```

## NVA image notes

The default `nva_image_name` is `Ubuntu 22.04 LTS`, which is a placeholder —
you have to configure `iptables`/`nftables` yourself after first boot. For
plug-and-play inspection, pass one of the marketplace NVA Firewall images:

- pfSense
- OPNsense
- Sophos UTM
- Fortinet FortiGate (BYOL)
- VyOS

(See **Marketplace > NVA Firewall** in the console for the live list.)

## When to pick this over the native-firewall variant

See `../hub-spoke-native-firewall/README.md` for the comparison table. Short
version: pick the NVA path when you need L7, IDS, VPN termination, or
custom NAT rules.
