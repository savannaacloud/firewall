# spoke-test — every service on one spoke

One-shot Terraform that exercises every typed resource the
`savannaacloud/sws` provider ships. Use it as:

- a **smoke-test** rig before bumping provider versions
- a **seed** for a demo / training environment
- a **post-upgrade verification** after a regional kolla redeploy

Single spoke network (`10.50.0.0/24`) carries all the services, so you
can flip between them in the console without hopping projects.

## What it deploys

| # | Section | Resources | What it creates |
|---|---|---|---|
| 1 | Networking | `sws_network`, `sws_subnet`, `sws_router`, `sws_router_interface`, `sws_floating_ip` | The spoke VPC + a public IP for the web tier |
| 2 | Security | `sws_security_group` + 4× `sws_security_group_rule` | Web SG allowing 80 / 443 / 22 / ICMP |
| 3 | Compute | `sws_keypair`, 2× `sws_instance` | Ubuntu 22.04 LTS web-1 (with public IP) + web-2 (private) |
| 4 | Block Storage | `sws_volume`, `sws_volume_attachment`, `sws_volume_snapshot` | 20 GB SSD attached to web-1 + a baseline snapshot |
| 5 | Object Storage | `sws_object_bucket` | One versioned bucket for static assets |
| 6 | Managed DB | `sws_managed_database` | PostgreSQL 16 on `r1.medium`, 20 GB |
| 7 | Load Balancer | `sws_load_balancer` + `sws_lb_listener` + `sws_lb_pool` + 2× `sws_lb_member` + `sws_lb_health_monitor` | HTTP LB fronting both web instances with `/` health check |
| 8 | DNS | `sws_dns_zone`, 2× `sws_dns_record`, `sws_private_dns_zone` | Public zone for your domain + A records pointing at the LB IP + private zone for internal service discovery |
| 9 | Tier-3 services | `sws_cache`, `sws_queue`, `sws_file_storage`, `sws_bastion` | Redis cache, RabbitMQ queue, NFS file storage, SSH bastion host |
| 10 | Kubernetes (opt-in) | `sws_kubernetes_cluster` (commented in `main.tf`) | 1-master + 2-worker k8s cluster — uncomment to enable |

Total **23 resources** by default (38 if you uncomment Kubernetes).

## Prerequisites

1. **Savannaa account** with API access (Account → API Keys in the console).
2. **Terraform ≥ 1.4** locally (we need protocol-6 support; v1.2.x will
   reject the provider).
3. (Optional) **SSH public key** if you want to log in to the web/bastion
   instances.
4. **A domain you own** for the DNS section. If you don't have one,
   change `var.domain_name` to `spoke-test.example.com` (the records
   create harmlessly under that placeholder zone and don't conflict with
   anything real).
5. **Quota headroom**: this example creates ~30 OpenStack-side objects.
   On a fresh account the defaults are 10 instances / 20 cores / 20
   security-group rules / 5 floating IPs / 10 networks — comfortably
   inside the limits. If you've stood up other examples, run `terraform
   destroy` on them first.

## Step-by-step

```bash
# 1. Clone the repo (or git pull if you already have it)
git clone https://github.com/savannaacloud/firewall.git
cd firewall/spoke-test     # this directory

# 2. Set credentials + region (env-var driven, never hardcoded)
export SWS_API_URL=https://savannaa.com
export SWS_API_KEY=<your-api-key>
export SWS_REGION=ng-lagos-1     # or ng-abuja-1

# 3. Initialise — downloads the provider from the Registry
terraform init

# 4. Preview — confirm what will be created
terraform plan \
  -var "ssh_public_key=$(cat ~/.ssh/id_rsa.pub)" \
  -var "domain_name=mydomain.example.com"

# 5. Apply — this takes ~3-5 minutes (LB + DB are the slow ones)
terraform apply -auto-approve \
  -var "ssh_public_key=$(cat ~/.ssh/id_rsa.pub)" \
  -var "domain_name=mydomain.example.com"

# 6. Read the outputs (instance IPs, IDs, public IP, summary)
terraform output
terraform output summary

# 7. Spot-check in the console
#    Compute > Instances   — 2× spoke-test-web-N (+ bastion)
#    Storage > Volumes     — 1× spoke-test-data-vol attached to web-1
#    Storage > Snapshots   — 1× spoke-test-data-vol-initial
#    Storage > Buckets     — spoke-test-assets
#    Database              — spoke-test-pg, ACTIVE
#    Networking > LBs      — spoke-test-lb with 2 healthy members
#    Networking > DNS      — your zone with www + apex A records
#    Networking > Cache    — spoke-test-cache
#    Networking > Queue    — spoke-test-events
#    Networking > FileStorage — spoke-test-share
#    Networking > Bastion  — spoke-test-bastion

# 8. SSH in via the bastion (if you set ssh_public_key)
ssh -J ubuntu@<bastion-public-ip> ubuntu@<web-1-private-ip>

# 9. Tear it all down when you're done
terraform destroy -auto-approve \
  -var "ssh_public_key=$(cat ~/.ssh/id_rsa.pub)" \
  -var "domain_name=mydomain.example.com"
```

## Variables you can tune

| Variable | Default | Notes |
|---|---|---|
| `ssh_public_key` | `""` | Empty disables keypair create. Set to enable SSH. |
| `domain_name` | `spoke-test.example.com` | Public DNS zone. Override with a domain you own. |
| `db_admin_password` | `ChangeMe-Spoke-Test-2026` | PostgreSQL admin password. **Change for any non-throwaway use.** |
| `cache_password` | `ChangeMe-Cache-2026` | Redis AUTH password. **Change for any non-throwaway use.** |

## Verified vs experimental coverage

Everything in this example was either typed-attribute v0.1-v0.3 or
recently exercised end-to-end (the Tier-3 four):

| Resource | State | Notes |
|---|---|---|
| Network / subnet / router / floating-IP | ✅ verified |  |
| Security groups + rules | ✅ verified | Backend now idempotent on duplicate-detect (PR #301) |
| Keypair / instance | ✅ verified |  |
| Volume / attachment / snapshot | ✅ verified |  |
| Object bucket | ✅ verified | Abuja RGW, Lagos Swift — both registered (memory project_abuja_rgw.md) |
| Managed database | ✅ verified | PR #288 plan-resolution + pricing |
| Load balancer suite | ✅ verified | PR #129 / #141 |
| DNS public + record | ✅ verified | Designate-backed |
| Private DNS zone | 🟡 Tier-3 generic | Uses `config = jsonencode(...)` |
| Cache / queue / file storage / bastion | 🟡 Tier-3 generic | All four should work but each may need backend `_unpack_config` if a 400 surfaces (the pattern that fixed vpc_peering in PR #300 / #303) |
| Kubernetes cluster | 🟡 opt-in, heavy | Uncomment when you have ~10 min and quota for 3 m1.medium |

If a Tier-3 resource errors with `400 ... is required`, that's the
backend not unpacking `config` JSON before reading top-level fields.
The fix pattern is in `routers/vpc_peering.py:_unpack_config()` — copy
it into the matching `routers/<service>.py` and the apply unblocks.

## Common gotchas

- **DNS zone create + you don't own the domain**: the record creates
  succeed (it's just Designate) but nothing resolves publicly. Either
  use a domain you own or accept the example zone is a sandbox.
- **LB pool members take ~30 s to go ACTIVE** after the instance boots.
  First `terraform plan` after apply may show a drift on member status;
  re-running `apply` against the up-to-date state is a no-op.
- **Volume snapshot before format** — the example snapshots an
  unformatted volume on purpose. If you want a post-format baseline,
  SSH in, run `mkfs.ext4 /dev/vdb`, then `terraform taint
  sws_volume_snapshot.data_initial && terraform apply`.
- **Object bucket name collisions** — `spoke-test-assets` is
  project-scoped so multiple customers can each create one. If you've
  already created a bucket with this name in this project, destroy or
  rename before retrying.

## Composing with the other examples

Once spoke-test is up, you can run `../native/` or `../nva/` in a
sibling directory — they each create their own networks under
non-overlapping CIDRs (10.10/16 and 10.20/16 respectively, vs this
example's 10.50/16). Peer them with `sws_vpc_peering` if you want to
demo cross-spoke traffic.
