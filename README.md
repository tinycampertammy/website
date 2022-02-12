# website

This document describes how to deploy the website for tinycampertammy.de. The website is backed by [wordpress](https://wordpress.org) and hosted on [Hetzner Cloud](https://www.hetzner.com/cloud) using the [wordpress-operator](https://github.com/bitpoke/wordpress-operator) and bootstrapped via [Terraform](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs) and [k3sup](https://github.com/alexellis/k3sup). TLS certificates are handled [cert-manager](https://github.com/jetstack/cert-manager) using [Letsencrypt CA](https://letsencrypt.org).

<!-- generate me with markdown-toc 
```bash
// source: https://github.com/jonschlinkert/markdown-toc
markdown-toc -i --maxdepth 2 README.md
Do NOT TOUCH anything between the toc comments because this is used as a `marker` where to place the toc for markdown-toc.
```
-->

**TOC**:

<!-- toc -->

- [Prerequisites](#prerequisites)
- [Deployment](#deployment)
- [Maintenance](#maintenance)
- [Undeploy](#undeploy)
- [See Also](#see-also-1)

<!-- tocstop -->

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

### K3sup

Install k3sup via go install or follow the [official installation instructions](https://github.com/alexellis/k3sup#download-k3sup-tldr):

```bash
go install github.com/alexellis/k3sup@latest
```

## Deployment

### Terraform

```bash
cd infra/
export DEPLOYMENT_NAME="website-staging"
terraform init -var="hcloud_token=$HCLOUD_TOKEN" -var="ssh_key=$HCLOUD_SSH_KEY" -var="$DEPLOYMENT_NAME"
terraform plan -var="hcloud_token=$HCLOUD_TOKEN" -var="ssh_key=$HCLOUD_SSH_KEY" -var="$DEPLOYMENT_NAME"

```

If you agree to the plan proposed by `terraform plan` you can create the infrastructure:

```bash
terraform apply -var="hcloud_token=$HCLOUD_TOKEN" -var="ssh_key=$HCLOUD_SSH_KEY" -var="$DEPLOYMENT_NAME"
```

### k3s

Use the terraform output command to install k3s:

```bash
$(terraform output -raw deploy_k3s)
```

Test if you can reach the kubernetes cluster:

```shell
$ export KUBECONFIG=$PWD/kubeconfig
$ kubectl get pods
No resources found in default namespace.
$ echo $?
0
```

Add an entry in the ssh config (optional):
```bash
$ printf %s\\n "$(terraform output -raw ssh_config)" | tee -a ~/.ssh/config
Host <deployment-name>
  Hostname <some-ip>
  IdentityFile <path-to-ssh-file>
  IdentitiesOnly Yes
  User root
```

### Wordpress

Now what we have a working k3s cluster we can finally install `Wordpress` on it.
The following installation commands are mostly derived from [bitpoke/stack](https://github.com/bitpoke/stack).

Add bitpoke `helm repository`:

```bash
helm repo add bitpoke https://helm-charts.bitpoke.io
helm repo update
```

Install `cert-manager` and two `ClusterIssuer`s. One for letsencrypt staging and one for production.

```bash
export CERT_MANAGER_VERSION=1.6.1
helm repo add jetstack https://charts.jetstack.io
helm repo update

kubectl create namespace cert-manager
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v$CERT_MANAGER_VERSION/cert-manager.crds.yaml

helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v$CERT_MANAGER_VERSION


export EMAIL="todo"
cat << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    email: ${EMAIL}
    preferredChain: ""
    privateKeySecretRef:
      name: letsencrypt-staging
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    solvers:
    - http01:
        ingress:
          class: bitpoke-stack
EOF
cat << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    email: ${EMAIL}
    preferredChain: ""
    privateKeySecretRef:
      name: letsencrypt-production
    server: https://acme-v02.api.letsencrypt.org/directory
    solvers:
    - http01:
        ingress:
          class: bitpoke-stack
EOF
```

// TODO: is this required ?
```
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/application/c8e2959e57a02b3877b394984a288f9178977d8b/config/crd/bases/app.k8s.io_applications.yaml
```

Install stack:

```bash
export STACK_VERSION=0.12.1
helm install \
    stack bitpoke/stack \
    --create-namespace \
    --namespace bitpoke-stack \
    --version v$STACK_VERSION \
    -f https://raw.githubusercontent.com/bitpoke/stack/v$STACK_VERSION/presets/minikube.yaml
```

Install wordpress site:

> **NOTE:** Use `letsencrypt-staging` until you know your setup is working properly. Otherwise you will hit the letsencrypt rate limit. Then use `letsencrypt-production`.

export DOMAIN="e.g. wordpress.yourdomain.de"

```bash
helm install \
    mysite bitpoke/wordpress-site \
    --version v$STACK_VERSION \
    --set "site.domains[0]=${DOMAIN}" \
    --set 'site.issuerName=letsencrypt-staging' \
    --set 'tls.issuerName=letsencrypt-staging'
```

At this point (might take some minutes) you should have the following state in your kubernetes cluster: a working `wordpress` and `mysqlcluster` CR as well as a ready `Certificate`.

```shell
$ kubectl get wordpresses.wordpress.presslabs.org,mysqlclusters.mysql.presslabs.org -A
NAMESPACE   NAME                                       IMAGE   WP-CRON
default     wordpress.wordpress.presslabs.org/mysite           True

NAMESPACE   NAME                                      READY   REPLICAS   AGE
default     mysqlcluster.mysql.presslabs.org/mysite   True    1          10m
```

```shell
$ kubectl tree certificate mysite-tls
NAMESPACE  NAME                                   READY  REASON  AGE
default    Certificate/mysite-tls                 True   Ready   3m27s
default    └─CertificateRequest/mysite-tls-bq9kh  True   Issued  3m26s
default      └─Order/mysite-tls-bq9kh-1964038611  -              3m26s
```

As soon as your certificate is ready you can issue a HTTP request against your website. Because we are still using the `letsencrypt-staging` ClusterIssuer the TLS certificate is not valid, but this is expected.
That means that the certificate issueing using Letsencrypt works.

```shell
$ curl -vkL https://${DOMAIN} 2>&1 |grep -A 5 "Server certificate"
* Server certificate:
*  subject: CN=<domain>
*  start date: Feb 12 07:41:47 2022 GMT
*  expire date: May 13 07:41:46 2022 GMT
*  issuer: C=US; O=(STAGING) Let's Encrypt; CN=(STAGING) Artificial Apricot R3
*  SSL certificate verify result: unable to get local issuer certificate (20), continuing anyway.
* Using HTTP2, server supports multi-use
```

Its time for a valid TLS certificate so we will use the `letsencrypt-production` issuer now:

```bash
helm upgrade \
    mysite bitpoke/wordpress-site \
    --set 'site.issuerName=letsencrypt-production' \
    --set 'tls.issuerName=letsencrypt-production'
```

You should be able to visit your website at https://${DOMAIN} now 😃.
Better be quick and create a Wordpress user because now that the site is exposed to the internet everyone can create a user as well.

### See Also

- [Offcial Bitpoke documentation](https://www.bitpoke.io/docs/stack/how-to/deploy-wordpress-on-stack/)

### Troubleshooting

#### Letsencrypt certificate not issued

```shell
$ kubectl logs -n cert-manager -l app.kubernetes.io/component=controller,app.kubernetes.io/instance=cert-manager
```

#### Debugging the wordpress pod

There is a shell in the wordpress container which is nice for debugging but bad for security:

```bash
$ kubectl exec -it mysite-8549bfbbc6-qxmb9 -c wordpress sh
kubectl exec [POD] [COMMAND] is DEPRECATED and will be removed in a future version. Use kubectl exec [POD] -- [COMMAND] instead.
$ ls
web  wp-cli.yml
```

## Maintenance

### Updating Wordpress version

How to update wordpress version:

```bash
$ helm upgrade mysite bitpoke/wordpress-site \
  --set 'image.repository=bitpoke/wordpress-runtime' \
  --set 'image.tag=5.9'
```

See available tags here: https://hub.docker.com/r/bitpoke/wordpress-runtime/tags

### Bitpoke chart updates

You can search for the latest chart version

```shell
$ helm repo update
$ helm search repo bitpoke
NAME                            CHART VERSION   APP VERSION     DESCRIPTION
bitpoke/bitpoke                 1.8.1           1.8.1           The Bitpoke App for WordPress provides a versat...
bitpoke/mysql-cluster           0.6.2           v0.6.2          A Helm chart for easy deployment of a MySQL clu...
bitpoke/mysql-operator          0.6.2           v0.6.2          A helm chart for Bitpoke Operator for MySQL
bitpoke/stack                   0.12.1          v0.12.1         Your Open-Source, Cloud-Native WordPress Infras...
bitpoke/wordpress-operator      0.12.1          v0.12.1         Bitpoke WordPress Operator Helm Chart
bitpoke/wordpress-site          0.12.1          v0.12.1         Helm chart for deploying a WordPress site on Bi...
```

## Undeploy

If you don't need the setup anymore, you can delete it with the following command. But make sure to remove the delete protection on the server first, otherwise terraform will not be able to delete it. This serves as an extra layer of protection so that you don't remove the cluster by accident.

```bash
terraform destroy -var="hcloud_token=$HCLOUD_TOKEN" -var="ssh_key=$HCLOUD_SSH_KEY" -var="$DEPLOYMENT_NAME"
```

## See Also

[bitpoke wordpress-operator](https://github.com/bitpoke/wordpress-operator)

[Hetzner Cloud](https://www.hetzner.com/cloud)[Terraform](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs)

[wordpress](https://wordpress.org)

[CloudInit](https://cloudinit.readthedocs.io/en/latest)
