###############################################################################
#  spoke-test — one-shot deploy of every typed Savannaa resource on a single
#  spoke network. Use it as a smoke-test rig before changing provider versions,
#  to seed a demo environment, or to verify a region after an upgrade.
#
#  Sections:
#    1. Networking       (network, subnet, router, floating-IP)
#    2. Security         (security groups + rules)
#    3. Compute          (keypair, 2× instance, public IP)
#    4. Block Storage    (volume, attachment, snapshot)
#    5. Object Storage   (bucket)
#    6. Managed Database (postgres)
#    7. Load Balancer    (LB + listener + pool + members + monitor)
#    8. DNS              (public zone + A records)
#    9. Tier-3 services  (cache, queue, file-storage, bastion, vpc-peering)
#   10. Kubernetes       (template + cluster) — heavy, OPT-IN via -var
#
#  Provider: savannaacloud/sws ~> 0.4
###############################################################################

locals {
  prefix = "spoke-test"
}

# ── 1. Networking ─────────────────────────────────────────────────────────
resource "sws_network" "spoke" {
  name = "${local.prefix}-net"
  cidr = "10.50.0.0/24"
}

resource "sws_subnet" "spoke" {
  name       = "${local.prefix}-subnet"
  network_id = sws_network.spoke.id
  cidr       = "10.50.0.0/24"
  gateway_ip = "10.50.0.1"
  dns_nameservers = ["8.8.8.8", "1.1.1.1"]
}

resource "sws_router" "spoke" {
  name = "${local.prefix}-router"
}

resource "sws_router_interface" "spoke" {
  router_id = sws_router.spoke.id
  subnet_id = sws_subnet.spoke.id
}

resource "sws_floating_ip" "web" {
  description = "Public IP for web-1"
}

# ── 2. Security ───────────────────────────────────────────────────────────
resource "sws_security_group" "web" {
  name        = "${local.prefix}-web-sg"
  description = "Web tier — 80/443 from anywhere, 22 from anywhere (tighten in prod)"
}

resource "sws_security_group_rule" "web_http" {
  security_group_id = sws_security_group.web.id
  direction         = "ingress"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  description       = "HTTP from anywhere"
}

resource "sws_security_group_rule" "web_https" {
  security_group_id = sws_security_group.web.id
  direction         = "ingress"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "sws_security_group_rule" "web_ssh" {
  security_group_id = sws_security_group.web.id
  direction         = "ingress"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "sws_security_group_rule" "web_icmp" {
  security_group_id = sws_security_group.web.id
  direction         = "ingress"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
}

# ── 3. Compute ────────────────────────────────────────────────────────────
data "sws_image" "ubuntu" { name = "Ubuntu 22.04 LTS" }
data "sws_plan"  "small"  { name = "m1.small" }

resource "sws_keypair" "admin" {
  count      = var.ssh_public_key == "" ? 0 : 1
  name       = "${local.prefix}-admin"
  public_key = var.ssh_public_key
}

resource "sws_instance" "web" {
  count      = 2
  name       = "${local.prefix}-web-${count.index + 1}"
  plan       = data.sws_plan.small.name
  image      = data.sws_image.ubuntu.id
  network_id = sws_network.spoke.id
  keypair    = length(sws_keypair.admin) > 0 ? sws_keypair.admin[0].name : null
  public_ip  = count.index == 0   # only web-1 gets a public IP by default
}

# ── 4. Block Storage ──────────────────────────────────────────────────────
resource "sws_volume" "data" {
  name        = "${local.prefix}-data-vol"
  size_gb     = 20
  volume_type = "gp-ssd"
  description = "Shared data volume attached to web-1"
}

resource "sws_volume_attachment" "data" {
  volume_id   = sws_volume.data.id
  instance_id = sws_instance.web[0].id
  device      = "/dev/vdb"
}

resource "sws_volume_snapshot" "data_initial" {
  volume_id = sws_volume.data.id
  name      = "${local.prefix}-data-vol-initial"
  # Created before the attachment is exercised — captures an empty
  # post-format state. Useful as a baseline for rollback drills.
  depends_on = [sws_volume_attachment.data]
}

# ── 5. Object Storage ─────────────────────────────────────────────────────
resource "sws_object_bucket" "assets" {
  name = "${local.prefix}-assets"
  config = jsonencode({
    versioning = true
  })
}

# ── 6. Managed Database ───────────────────────────────────────────────────
resource "sws_managed_database" "app" {
  name = "${local.prefix}-pg"
  config = jsonencode({
    engine         = "postgresql"
    version        = "16"
    plan           = "r1.medium"     # memory-optimised — see PR #288
    storage_gb     = 20
    network_id     = sws_network.spoke.id
    admin_user     = "spoke_admin"
    admin_password = var.db_admin_password
    high_availability = false
    backup_retention_days = 7
  })
}

# ── 7. Load Balancer ──────────────────────────────────────────────────────
resource "sws_load_balancer" "web" {
  name              = "${local.prefix}-lb"
  vip_subnet_id     = sws_subnet.spoke.id
  description       = "Public LB fronting web-1 and web-2"
}

resource "sws_lb_listener" "http" {
  load_balancer_id = sws_load_balancer.web.id
  name             = "${local.prefix}-listener-80"
  protocol         = "HTTP"
  protocol_port    = 80
}

resource "sws_lb_pool" "web" {
  listener_id  = sws_lb_listener.http.id
  name         = "${local.prefix}-pool"
  protocol     = "HTTP"
  lb_algorithm = "ROUND_ROBIN"
}

resource "sws_lb_member" "web" {
  count          = 2
  pool_id        = sws_lb_pool.web.id
  address        = sws_instance.web[count.index].ip_address
  protocol_port  = 80
  subnet_id      = sws_subnet.spoke.id
  name           = "${local.prefix}-member-${count.index + 1}"
}

resource "sws_lb_health_monitor" "web" {
  pool_id        = sws_lb_pool.web.id
  type           = "HTTP"
  delay          = 5
  timeout        = 3
  max_retries    = 3
  url_path       = "/"
  expected_codes = "200"
}

# ── 8. DNS ────────────────────────────────────────────────────────────────
resource "sws_dns_zone" "public" {
  name        = var.domain_name
  description = "Public zone for ${var.domain_name}"
  ttl         = 3600
  email       = "admin@${var.domain_name}"
}

resource "sws_dns_record" "www" {
  zone_id = sws_dns_zone.public.id
  name    = "www.${var.domain_name}."
  type    = "A"
  ttl     = 300
  records = [sws_floating_ip.web.address]
}

resource "sws_dns_record" "root" {
  zone_id = sws_dns_zone.public.id
  name    = "${var.domain_name}."
  type    = "A"
  ttl     = 300
  records = [sws_floating_ip.web.address]
}

resource "sws_private_dns_zone" "internal" {
  name = "internal.${local.prefix}.lan"
  config = jsonencode({
    description = "Private DNS for in-spoke service discovery"
    ttl         = 60
  })
}

# ── 9. Tier-3 services ────────────────────────────────────────────────────
resource "sws_cache" "session" {
  name = "${local.prefix}-cache"
  config = jsonencode({
    engine          = "redis"
    plan            = "small"
    network_id      = sws_network.spoke.id
    auth_password   = var.cache_password
    persistence     = false
    eviction_policy = "allkeys-lru"
  })
}

resource "sws_queue" "events" {
  name = "${local.prefix}-events"
  config = jsonencode({
    engine     = "rabbitmq"
    plan       = "small"
    network_id = sws_network.spoke.id
  })
}

resource "sws_file_storage" "shared" {
  name = "${local.prefix}-share"
  config = jsonencode({
    size_gb    = 100
    network_id = sws_network.spoke.id
  })
}

resource "sws_bastion" "jump" {
  name = "${local.prefix}-bastion"
  config = jsonencode({
    network_id = sws_network.spoke.id
    plan       = "m1.small"
    cidr_allow = ["0.0.0.0/0"]
  })
}

# ── 10. Kubernetes (OPT-IN — heavy, ~5-10 min to provision) ──────────────
# Uncomment to deploy a 1-master + 2-worker k8s cluster. Make sure the
# region has Magnum healthy and the project has compute quota for 3 m1.medium
# instances + cinder volumes for the cluster.
#
# resource "sws_kubernetes_cluster" "demo" {
#   name = "${local.prefix}-k8s"
#   config = jsonencode({
#     node_count      = 2
#     master_count    = 1
#     keypair         = length(sws_keypair.admin) > 0 ? sws_keypair.admin[0].name : null
#     network_driver  = "calico"
#     flavor_id       = "m1.medium"
#     master_flavor_id = "m1.medium"
#     fixed_subnet    = sws_subnet.spoke.id
#   })
# }
