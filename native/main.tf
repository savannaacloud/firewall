###############################################################################
#  Hub-and-spoke topology with 4 hubs + 1 central spoke, using the platform's
#  native firewall (security groups) — no NVA instance.
#
#  Topology:
#                       hub-1 ──┐
#                       hub-2 ──┤
#                                ├──► spoke (central / workload)
#                       hub-3 ──┤
#                       hub-4 ──┘
#
#  Each hub is peered to the spoke. Security groups attached to instances in
#  each network enforce east-west policy ("native firewall"):
#    - spoke   → accepts traffic from any of the 4 hubs on 22/80/443
#    - hub-N   → accepts traffic only from the spoke (no cross-hub paths)
#
#  This is the classic flat-peering pattern: no inspection point, low latency,
#  fully managed by SDN. For deep packet inspection see ../hub-spoke-nva/.
###############################################################################

terraform {
  required_providers {
    sws = {
      source  = "savannaacloud/sws"
      version = "~> 0.4"
    }
  }
}

provider "sws" {}

locals {
  hubs = ["hub-1", "hub-2", "hub-3", "hub-4"]

  # Distinct CIDR per hub so routes don't collide with the spoke.
  hub_cidrs = {
    "hub-1" = "10.10.1.0/24"
    "hub-2" = "10.10.2.0/24"
    "hub-3" = "10.10.3.0/24"
    "hub-4" = "10.10.4.0/24"
  }
}

# ── Networks ──────────────────────────────────────────────────────────────
resource "sws_network" "spoke" {
  name = "spoke"
  cidr = "10.10.0.0/24"
}

resource "sws_network" "hub" {
  for_each = toset(local.hubs)
  name     = each.value
  cidr     = local.hub_cidrs[each.value]
}

# ── Peerings: each hub ↔ spoke ────────────────────────────────────────────
resource "sws_vpc_peering" "hub_to_spoke" {
  for_each = sws_network.hub

  name = "peering-${each.value.name}-to-spoke"
  config = jsonencode({
    local_network_id = each.value.id
    peer_network_id  = sws_network.spoke.id
  })
}

# ── Native firewall: security groups ──────────────────────────────────────
# Spoke SG: accept SSH/HTTP/HTTPS from every hub CIDR.
resource "sws_security_group" "spoke" {
  name        = "sg-spoke"
  description = "Spoke workload — accepts traffic from any hub"
}

resource "sws_security_group_rule" "spoke_from_hub" {
  for_each = local.hub_cidrs

  security_group_id = sws_security_group.spoke.id
  direction         = "ingress"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 443
  remote_ip_prefix  = each.value
  description       = "Allow ${each.key} -> spoke"
}

# Hub SGs: only accept return traffic from the spoke (no cross-hub talk).
resource "sws_security_group" "hub" {
  for_each    = toset(local.hubs)
  name        = "sg-${each.value}"
  description = "Hub ${each.value} — accepts traffic only from spoke"
}

resource "sws_security_group_rule" "hub_from_spoke" {
  for_each = sws_security_group.hub

  security_group_id = each.value.id
  direction         = "ingress"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 443
  remote_ip_prefix  = sws_network.spoke.cidr
  description       = "Allow spoke -> ${each.key}"
}

# ── Outputs ───────────────────────────────────────────────────────────────
output "spoke_network_id" { value = sws_network.spoke.id }
output "hub_network_ids"  { value = { for k, v in sws_network.hub : k => v.id } }
output "peering_ids"      { value = { for k, v in sws_vpc_peering.hub_to_spoke : k => v.id } }
