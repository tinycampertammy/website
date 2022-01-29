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
}

output "ssh_command" {
  description = "use this command to SSH into the VM (hint: remove the .pub)"
  value = "ssh root@${hcloud_server.web.ipv4_address} -i ${var.ssh_key}"
}
