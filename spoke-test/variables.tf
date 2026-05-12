variable "ssh_public_key" {
  description = "Public key to inject into the keypair for SSH access into instances."
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Public DNS zone to create (must be a domain you own). Skip if you don't need DNS."
  type        = string
  default     = "spoke-test.example.com"
}

variable "db_admin_password" {
  description = "Initial admin password for the managed database."
  type        = string
  default     = "ChangeMe-Spoke-Test-2026"
  sensitive   = true
}

variable "cache_password" {
  description = "AUTH password for the Redis cache."
  type        = string
  default     = "ChangeMe-Cache-2026"
  sensitive   = true
}
