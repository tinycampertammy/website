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
  name  = "web-server-1"
  image = "ubuntu-20.04"
  delete_protection = true
  rebuild_protection = true
  server_type = "cx11"
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

# TODO: create a ticket on k3sup to escape k3s version in github download
# k3sup install --user root --ip 65.21.154.121 --ssh-key /Users/i512777/dev/coding/personal/personal-secrets/tinycampertammy.de/website-server --k3s-version v1.21.9+k3s
# ...
# ssh: curl -sLS https://get.k3s.io | INSTALL_K3S_EXEC='server  --tls-san 65.21.154.121 ' INSTALL_K3S_VERSION='v1.21.9+k3s' sh -
# [INFO]  Using v1.21.9+k3s as release
# [INFO]  Downloading hash https://github.com/k3s-io/k3s/releases/download/v1.21.9+k3s/sha256sum-amd64.txt
# Error: error received processing command: Process exited with status 22


output "deploy_k3s" {
  description = "use this command to deploy k3s"
  value = "k3sup install --user root --ip ${hcloud_server.web.ipv4_address} --ssh-key ${trim(var.ssh_key, ".pub")} --k3s-version v1.21.9%2Bk3s1"
}
