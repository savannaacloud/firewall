###############################################################################
#  Hub-and-spoke topology with 1 hub + 4 spokes, traffic inspected by a
#  Network Virtual Appliance (NVA) instance on the hub.
#
#  Topology:
#                  ┌────► spoke-1
#                  ├────► spoke-2
#    hub ─► NVA ──┤
#                  ├────► spoke-3
#                  └────► spoke-4
#
#  Hub is peered to every spoke. The NVA instance lives on the hub and is the
#  enforcement point — replace the placeholder image with a marketplace NVA
#  firewall image (pfSense, OPNsense, Fortinet etc.) for real inspection.
#
#  Security groups segment the spokes so the only ingress path is the NVA's
#  fixed IP. This pushes all cross-spoke + north-south traffic through the
#  appliance.
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

variable "ssh_public_key" {
  description = "Public key to inject for SSH into the NVA."
  type        = string
  default     = ""
}

variable "nva_image_name" {
  description = "Name of the marketplace image to boot as the NVA (pfSense, OPNsense, Sophos, etc.). Default is Ubuntu — replace for production."
  type        = string
  default     = "Ubuntu 22.04 LTS"
}

locals {
  spokes = ["spoke-1", "spoke-2", "spoke-3", "spoke-4"]

  spoke_cidrs = {
    "spoke-1" = "10.20.1.0/24"
    "spoke-2" = "10.20.2.0/24"
    "spoke-3" = "10.20.3.0/24"
    "spoke-4" = "10.20.4.0/24"
  }

  hub_cidr = "10.20.0.0/24"
}

# ── Networks ──────────────────────────────────────────────────────────────
resource "sws_network" "hub" {
  name = "hub"
  cidr = local.hub_cidr
}

resource "sws_network" "spoke" {
  for_each = toset(local.spokes)
  name     = each.value
  cidr     = local.spoke_cidrs[each.value]
}

# ── Peerings: each spoke ↔ hub ────────────────────────────────────────────
resource "sws_vpc_peering" "spoke_to_hub" {
  for_each = sws_network.spoke

  name = "peering-${each.value.name}-to-hub"
  config = jsonencode({
    local_network_id = each.value.id
    peer_network_id  = sws_network.hub.id
  })
}

# ── NVA instance on the hub ───────────────────────────────────────────────
data "sws_image" "nva" { name = var.nva_image_name }
data "sws_plan"  "nva" { name = "m1.medium" }     # 2 vCPU / 4 GB

resource "sws_keypair" "nva" {
  count      = var.ssh_public_key == "" ? 0 : 1
  name       = "nva-key"
  public_key = var.ssh_public_key
}

resource "sws_security_group" "nva" {
  name        = "sg-nva"
  description = "NVA — allow management + traffic from every spoke"
}

# Management: SSH from the public internet (tighten this prefix in prod).
resource "sws_security_group_rule" "nva_mgmt_ssh" {
  security_group_id = sws_security_group.nva.id
  direction         = "ingress"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  description       = "SSH management"
}

# Accept all traffic from every spoke (the NVA decides what to do with it).
resource "sws_security_group_rule" "nva_from_spoke" {
  for_each = local.spoke_cidrs

  security_group_id = sws_security_group.nva.id
  direction         = "ingress"
  protocol          = "tcp"
  port_range_min    = 1
  port_range_max    = 65535
  remote_ip_prefix  = each.value
  description       = "All TCP from ${each.key}"
}

resource "sws_instance" "nva" {
  name       = "nva"
  plan       = data.sws_plan.nva.name
  image      = data.sws_image.nva.id
  network_id = sws_network.hub.id
  keypair    = length(sws_keypair.nva) > 0 ? sws_keypair.nva[0].name : null
  public_ip  = true
}

# ── Spoke SGs: only the NVA's fixed IP can ingress ────────────────────────
resource "sws_security_group" "spoke" {
  for_each    = toset(local.spokes)
  name        = "sg-${each.value}"
  description = "${each.value} workloads — ingress only from NVA"
}

# We pin to the NVA's hub-side fixed IP rather than the whole hub CIDR so
# that any other future hub VM can't bypass the appliance.
resource "sws_security_group_rule" "spoke_from_nva" {
  for_each = sws_security_group.spoke

  security_group_id = each.value.id
  direction         = "ingress"
  protocol          = "tcp"
  port_range_min    = 1
  port_range_max    = 65535
  remote_ip_prefix  = "${sws_instance.nva.ip_address}/32"
  description       = "Allow NVA -> ${each.key}"
}

# ── Outputs ───────────────────────────────────────────────────────────────
output "hub_network_id"  { value = sws_network.hub.id }
output "spoke_network_ids" { value = { for k, v in sws_network.spoke : k => v.id } }
output "nva_ip"            { value = sws_instance.nva.ip_address }
output "peering_ids"       { value = { for k, v in sws_vpc_peering.spoke_to_hub : k => v.id } }
