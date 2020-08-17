#!/bin/bash
terraform plan -destroy -out=terraform.tfplan
terraform apply terraform.tfplan

# remove old files from initial deployment
rm -rf terraform.tfplan terraform.tfstate terraform.tfstate.backup
rm -rf *.tf
rm -rf *.txt
rm -rf ".terraform"
rm -rf ansible-percona-xtradb-cluster
rm -rf output
