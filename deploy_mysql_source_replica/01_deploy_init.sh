#!/bin/bash
### initialize digital ocean config ###
echo 'terraform {
  required_version = ">= 0.12"
}' > version.tf

echo 'variable "do_token" {}
variable "ssh_fingerprint" {}

provider "digitalocean" {
  token = var.do_token
}' > provider_do.tf

terraform init
