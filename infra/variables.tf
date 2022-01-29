variable "hcloud_token" {
  sensitive = true
}

variable "ssh_key" {
  default = "~/.ssh/id_rsa.pub"
}

variable "server_type" {
  default = "cx11"
}
