terraform {
  required_version = ">= 1.4"
  required_providers {
    sws = {
      source  = "savannaacloud/sws"
      version = "~> 0.4"
    }
  }
}

provider "sws" {}
