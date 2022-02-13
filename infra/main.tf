# original setup highyly inspired by: https://medium.com/@orestovyevhen/set-up-infrastructure-in-hetzner-cloud-using-terraform-ce85491e92d

terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
       version = "1.32.2"
    }
  }
  required_version = ">= 0.14.0"
}

provider "hcloud" {
  token = var.hcloud_token
}

resource "hcloud_ssh_key" "default" {
  name       = "website_key"
  public_key = file(var.ssh_key)
}

resource "hcloud_server" "web" {
  name  = var.name
  image = "ubuntu-20.04"
  delete_protection = true
  rebuild_protection = true
  server_type = "cx21"
  ssh_keys    = [hcloud_ssh_key.default.id]
  labels = {
    type = "web"
  }
  user_data = file("user_data.yml")
}

output "ssh_command" {
  description = "use this command to SSH into the VM"
  value = "ssh root@${hcloud_server.web.ipv4_address} -i ${trim(var.ssh_key, ".pub")}"
}

# It is important to use "--disable-traefik" to not install traefik. There is already an ingress class created by bitpoke/stack. Both canot work at the same time.
output "deploy_k3s" {
  description = "use this command to deploy k3s"
  value = "k3sup install --user root --ip ${hcloud_server.web.ipv4_address} --ssh-key ${trim(var.ssh_key, ".pub")} --k3s-version v1.21.9+k3s1 --k3s-extra-args '--disable traefik'"
}

output "ssh_config" {
  description = "use this inside your ssh config"
  value = "Host ${var.name}\n  Hostname ${hcloud_server.web.ipv4_address}\n  IdentityFile ${trim(var.ssh_key, ".pub")}\n  IdentitiesOnly Yes\n  User root"
}

output "dns" {
  description = "information about how to setup DNS"
  value = "Create a DNS A record and let it point to ${hcloud_server.web.ipv4_address}"
}
