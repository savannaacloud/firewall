output "network_id"      { value = sws_network.spoke.id }
output "subnet_id"       { value = sws_subnet.spoke.id }
output "router_id"       { value = sws_router.spoke.id }
output "web_public_ip"   { value = sws_floating_ip.web.address }

output "instance_ids"    { value = [for i in sws_instance.web : i.id] }
output "instance_ips"    { value = [for i in sws_instance.web : i.ip_address] }

output "load_balancer_id" { value = sws_load_balancer.web.id }
output "lb_listener_id"   { value = sws_lb_listener.http.id }

output "database_id"     { value = sws_managed_database.app.id }
output "cache_id"        { value = sws_cache.session.id }
output "queue_id"        { value = sws_queue.events.id }
output "file_storage_id" { value = sws_file_storage.shared.id }
output "bastion_id"      { value = sws_bastion.jump.id }

output "bucket_name"     { value = sws_object_bucket.assets.name }
output "dns_zone_id"     { value = sws_dns_zone.public.id }
output "private_zone_id" { value = sws_private_dns_zone.internal.id }

output "volume_id"          { value = sws_volume.data.id }
output "volume_snapshot_id" { value = sws_volume_snapshot.data_initial.id }

output "summary" {
  description = "Quick inventory of what got created"
  value = {
    networks  = 1
    subnets   = 1
    routers   = 1
    floating_ips = 1
    security_groups = 1
    security_group_rules = 4
    instances = length(sws_instance.web)
    volumes   = 1
    snapshots = 1
    buckets   = 1
    databases = 1
    caches    = 1
    queues    = 1
    file_shares = 1
    bastions  = 1
    lb        = 1
    lb_pools  = 1
    lb_members = length(sws_lb_member.web)
    lb_monitors = 1
    dns_zones = 1
    dns_records = 2
    private_dns_zones = 1
  }
}
