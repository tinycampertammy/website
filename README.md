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

### K3sup

Install k3sup via go install or follow the [official installation instructions](https://github.com/alexellis/k3sup#download-k3sup-tldr):

```bash
go install github.com/alexellis/k3sup@latest
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

### Destroy Infrastructure

If you don't need the setup anymore, you can delete it with the following command. But make sure to remove the delete protection on the server first, otherwise terraform will not be able to delete it. This serves as an extra layer of protection so that you don't remove the cluster by accident.

```bash
terraform destroy -var="hcloud_token=$HCLOUD_TOKEN" -var="ssh_key=$HCLOUD_SSH_KEY"
```

### Deploy k3s

Use output command of terraform apply to install k3s, it should look like:
```
deploy_k3s = "k3sup install --user root --ip <ip> --ssh-key <ssh-key>"
```

Test if you can reach the kubernetes cluster:

```shell
$ export KUBECONFIG=$PWD/kubeconfig
$ kubectl get pods
No resources found in default namespace.
$ echo $?
0
```

### Install Stack

```
helm repo add bitpoke https://helm-charts.bitpoke.io
helm repo update

export CERT_MANAGER_VERSION=1.6.1

helm repo add jetstack https://charts.jetstack.io
helm repo update

kubectl create namespace cert-manager
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v$CERT_MANAGER_VERSION/cert-manager.crds.yaml

helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v$CERT_MANAGER_VERSION

kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/application/c8e2959e57a02b3877b394984a288f9178977d8b/config/crd/bases/app.k8s.io_applications.yaml

export STACK_VERSION=0.12.0
helm install \
    stack bitpoke/stack \
    --create-namespace \
    --namespace bitpoke-stack \
    --version v$STACK_VERSION \
    -f https://raw.githubusercontent.com/bitpoke/stack/v$STACK_VERSION/presets/minikube.yaml

export STACK_VERSION=0.12.0
helm install \
    mysite bitpoke/wordpress-site \
    --version v$STACK_VERSION \
    --set 'site.domains[0]=www.example.com'
# the above does not work
helm install mysite presslabs/wordpress-site --create-namespace  --set "site.domains[0]=www.mysite.com"
```

### Install wordpress-operator

```shell
$ helm repo add bitpoke https://helm-charts.bitpoke.io
"bitpoke" has been added to your repositories

$ helm install wordpress-operator bitpoke/wordpress-operator
NAME: wordpress-operator
LAST DEPLOYED: Sat Jan 29 11:48:55 2022
NAMESPACE: default
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
WordPress Operator installed in default
```

Ensure the operator got installed:
```shell
$ kubectl get deployments.apps -l app.kubernetes.io/instance=wordpress-operator
NAME                 READY   UP-TO-DATE   AVAILABLE   AGE
wordpress-operator   1/1     1            1           4m21s
```

```shell
cat << EOF | kubectl apply -f -
apiVersion: wordpress.presslabs.org/v1alpha1
kind: Wordpress
metadata:
  name: mysite
spec:
  replicas: 1
  domains:
    - example.com
  code: # where to find the code
    emptyDir: {}
  media: # where to find the media files
    emptyDir: {}
  bootstrap: # wordpress install config
    env:
      - name: WORDPRESS_BOOTSTRAP_USER
        value: wordpress
      - name: WORDPRESS_BOOTSTRAP_PASSWORD
        value: wordpress
      - name: WORDPRESS_BOOTSTRAP_EMAIL
        value: wordpress@wordpress.org
      - name: WORDPRESS_BOOTSTRAP_TITLE
        value: wordpress
  # extra env variables for the WordPress container
  env:
    - name: DB_HOST
      value: mysql
    - name: DB_USER
      value: wordpress
    - name: DB_PASSWORD
      value: wordpress
    - name: DB_NAME
      value: wordpress
EOF
```

### Install mysql-operator

Deploy the mysql-operator:

```bash
helm repo add bitpoke https://helm-charts.bitpoke.io
helm install mysql-operator bitpoke/mysql-operator
```


Deploy the mysql database:

```bash
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
type: Opaque
stringData:
  # root password is required to be specified
  # TODO:
  ROOT_PASSWORD: wordpress
  ## application credentials that will be created at cluster bootstrap
  DATABASE: wordpress
  USER: wordpress
  PASSWORD: wordpress
EOF
# TODO: scale down to 1 replica
kubectl apply -f https://raw.githubusercontent.com/bitpoke/mysql-operator/master/examples/example-cluster.yaml
```

You should see following message in the mysite pod now:

```shell
$ kubectl logs mysite-8549bfbbc6-qxmb9 -c install-wp -f
Success: WordPress installed successfully.
```


## Troubleshooting

### Database Connectivity

This is just a symptom, but not the root cause:

```shell
$ kubectl logs -n default wordpress-operator-758bd4787c-7mh59 -f

_cron\": context deadline exceeded" "controller"="wp-cron-controller" "key"={"Namespace":"default","Name":"mysite"}
```

Instead check the website pod:
```shell
$ kubectl logs mysite-7d5f4c7669-kt47w -c install-wp
Error: Error establishing a database connection. This either means that the username and password information in your `wp-config.php` file is incorrect or we can’t contact the database server at `mysite-mysql`. This could mean your host’s database server is down.
```

### Worpress Config

The logs of the mysite pod show the following error for the install-wp init container:

```bash
$ kubectl logs mysite-bf9b59d4c-8sqtq -c install-wp -f
Error: The 'wordpress' email address is invalid.
```

The fix is to set spec.bootstrap.env.WORDPRESS_BOOTSTRAP_EMAIL to a valid email in the wordpress.presslabs.org instance mysite.

```bash
kubectl edit wordpresses.wordpress.presslabs.org mysite
```

### Wordpress Site not coming up

```shell
$ kubectl port-forward mysite-8549bfbbc6-qxmb9 9145
Forwarding from 127.0.0.1:9145 -> 9145
Forwarding from [::1]:9145 -> 9145
Handling connection for 9145
Handling connection for 9145
Handling connection for 9145
```

```shell
$ k get wordpresses.wordpress.presslabs.org
NAME     IMAGE   WP-CRON
mysite           True
# This is true for very troubleshoot so far

$ k logs mysite-8549bfbbc6-qxmb9 -f
2022/01/29 17:03:36 [error] 43#43: *1253 open() "/var/lib/nginx/html/index.html" failed (2: No such file or directory), client: 127.0.0.1, server: , request: "GET /index.html HTTP/1.1", host: "localhost:9145"

```


## Random Notes

- there is a shell in wordpress container, nice for debugging bad for security :/
```
k exec -it mysite-8549bfbbc6-qxmb9 -c wordpress sh
kubectl exec [POD] [COMMAND] is DEPRECATED and will be removed in a future version. Use kubectl exec [POD] -- [COMMAND] instead.
$ ls
web  wp-cli.yml
$
```

## See Also

[bitpoke wordpress-operator](https://github.com/bitpoke/wordpress-operator)

[Hetzner Cloud](https://www.hetzner.com/cloud)[Terraform](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs)

[wordpress](https://wordpress.org)

[CloudInit](https://cloudinit.readthedocs.io/en/latest)
