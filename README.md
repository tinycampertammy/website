# website

This document describes how to deploy the website for tinycampertammy.de. The website is backed by [wordpress](https://wordpress.org) and hosted on [Hetzner Cloud](https://www.hetzner.com/cloud) using the [wordpress-operator](https://github.com/bitpoke/wordpress-operator) and bootstrapped via [Terraform](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs).

## Prerequisites

### Terraform CLI

Follow the tutorial [Terraform CLI](https://learn.hashicorp.com/tutorials/terraform/install-cli#install-terraform)

or use these insructions for Mac OS:

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

### HCloud Setup & SSH Key

Get token from Hetzner Cloud by following this [tutorial](https://docs.hetzner.com/cloud/api/getting-started/generating-api-token/)

```bash
export HCLOUD_TOKEN=<TODO>
```

Create SSH key:

```bash
export HCLOUD_SSH_KEY=~/.ssh/hcloud_wordpress
ssh-keygen -t ed25519 -a 100 -f $HCLOUD_SSH_KEY
chmod 0644 $HCLOUD_SSH_KEY
```

## Setup Infrastructure

```bash
cd infra/
terraform init -var="hcloud_token=$HCLOUD_TOKEN" -var="ssh_key=$HCLOUD_SSH_KEY"
terraform plan -var="hcloud_token=$HCLOUD_TOKEN" -var="ssh_key=$HCLOUD_SSH_KEY"
```

If you agree to the plan proposed by `terraform plan` you can create the infrastructure:

```bash
terraform apply -var="hcloud_token=$HCLOUD_TOKEN" -var="ssh_key=$HCLOUD_SSH_KEY"
```

## Deploy It

## See Also

[bitpoke wordpress-operator](https://github.com/bitpoke/wordpress-operator)
[Hetzner Cloud](https://www.hetzner.com/cloud)[Terraform](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs)
[wordpress](https://wordpress.org)
