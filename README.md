# Kubernetes Voting App Deployment with Full Monitoring Stack (Prometheus, Grafana, Alertmanager)

## Project Overview

This project demonstrates how to deploy a production-ready Voting Application on Kubernetes using AWS EKS, with a complete observability stack powered by Prometheus, Grafana, and Alertmanager.

The objective is to:

* Deploy a scalable application on a managed Kubernetes control plane (EKS).
* Implement persistent storage using AWS EBS CSI.
* Expose services externally using an Ingress Controller (Traefik).
* Monitor both Kubernetes infrastructure and application-level metrics.
* Visualize performance and system health using Grafana dashboards.
* Configure Alertmanager to send real-time alerts to Slack.

This reflects a real-world DevOps environment where monitoring, alerting, and infrastructure are tightly integrated to ensure reliability and proactive incident response.

---

# Step A — EKS Setup and Kubernetes Deployment

## Prerequisites

Install the following tools on your local machine:

```bash
# Install kubectl
curl -o kubectl https://s3.us-west-2.amazonaws.com/amazon-eks/1.29.0/2024-01-04/bin/linux/amd64/kubectl
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Install eksctl
curl --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz
sudo mv eksctl /usr/local/bin/

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

---

## Step 1 — Configure AWS CLI and Create Infrastructure

Create an Access Key and Secret Key from AWS IAM, then configure locally:

```bash
aws configure
```

Enter:

* Access Key
* Secret Key
* Region: us-east-1
* Output: json

(Delete the keys after setup for security.)

Create IAM Role for EKS Control Plane with:

```
AmazonEKSClusterPolicy
```

Create a VPC with:

* CIDR block: `10.0.0.0/16`
* 2 Public Subnets
* 2 Private Subnets
* NAT Gateway (single AZ)
* Enable DNS Hostnames
* Configure Security Group

---

## Step 2 — Create EKS Cluster (Control Plane)

From AWS Console:

* Select **Custom Configuration**
* Select the IAM role created earlier
* Enable default add-ons:

  * kube-proxy
  * CoreDNS
  * VPC CNI
  * Node Monitoring Agent
  * EBS CSI Driver

Create the cluster (this takes several minutes).

---

## Step 3 — Create Worker Node Group

Create IAM Role for Worker Nodes with policies:

```
AmazonEKSWorkerNodePolicy
AmazonEC2ContainerRegistryReadOnly
AmazonEKS_CNI_Policy
AmazonSSMManagedInstanceCore
```

Inside the cluster:

* Go to **Compute → Node Group**
* Attach worker node IAM role
* AMI Type: Amazon Linux 2
* Instance Type: Minimum 2 vCPU (e.g., t3.medium)
* Disk Size: 20GB+
* Desired Nodes: 2
* Select all four subnets

Create the node group.

---

## Step 4 — Connect to the Cluster

Verify AWS configuration:

```bash
aws sts get-caller-identity
```

Join cluster:

```bash
aws eks update-kubeconfig --name eks-cluster --region us-east-1
```

Verify nodes:

```bash
kubectl get nodes
kubectl get pods -n kube-system
```

(Insert screenshot here showing nodes running.)

---

## Step 5 — Attach IAM Role to EBS CSI Driver (IRSA)

```bash
eksctl utils associate-iam-oidc-provider \
  --region us-east-1 \
  --cluster eks-cluster \
  --approve
```

```bash
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster eks-cluster \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve \
  --region us-east-1
```

Restart CSI controller:

```bash
kubectl rollout restart deployment ebs-csi-controller -n kube-system
```

---

## Step 6 — Deploy Voting Application Resources

### Install Traefik Ingress Controller

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

kubectl create namespace traefik

helm install traefik traefik/traefik -n traefik
```

---

### Create Application Manifests

Create Kubernetes manifests for:

* app-backend Deployment & Service
* MySQL Deployment & Service
* phpMyAdmin Deployment & Service

Create Secret (Base64 encode password):

```bash
echo -n "mypassword" | base64
```

---

### Create StorageClass for EBS

```bash
kubectl apply -f storageclass.yml
```

---

### Create Persistent Volume Claim

```bash
kubectl apply -f db-persistentvolumeclaim.yml
```

---

### Create Ingress Resource

Use dummy domain:

```
votingapp.xyz
```

Ingress routes traffic to the ClusterIP service.

---

### Apply All Manifests

```bash
kubectl apply -f kubernetes/
```

---

### Access Application

```bash
kubectl get svc -n traefik
```

Copy ELB DNS and map locally:

```bash
sudo vim /etc/hosts
```

Add:

```
<LOADBALANCER-IP> votingapp.xyz
```

Open browser:

```
http://votingapp.xyz
```

Application should load successfully.

---

# Step B — Monitoring Stack (Prometheus, Grafana, Alertmanager)

## Step 1 — Enable Metrics in Application

Enable `/metrics` endpoint using Spring Boot Actuator(for Java applications) in the application source code:

```
/actuator/prometheus
```

---

## Step 2 — Install kube-prometheus-stack

Create namespace:

```bash
kubectl create namespace monitoring
```

Add Helm repo:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

Install stack:

```bash
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring
```

This installs Prometheus, Grafana, Alertmanager, node-exporter, and kube-state-metrics.

---

## Step 3 — Expose Monitoring UIs

```bash
kubectl patch svc monitoring-kube-prometheus-prometheus \
  -n monitoring \
  -p '{"spec": {"type": "LoadBalancer"}}'
```

```bash
kubectl patch svc monitoring-grafana \
  -n monitoring \
  -p '{"spec": {"type": "LoadBalancer"}}'
```

```bash
kubectl patch svc monitoring-kube-prometheus-alertmanager \
  -n monitoring \
  -p '{"spec": {"type": "LoadBalancer"}}'
```

---

## Step 4 — Retrieve Admin Passwords

Grafana password:

```bash
kubectl get secret monitoring-grafana -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 --decode
```

---

## Step 5 — Apply ServiceMonitor

```bash
kubectl apply -f servicemonitor.yml
```

---

## Step 6 — Verify Target in Prometheus

Open Prometheus UI → Status → Targets and confirm application metrics appear.

---

## Step 7 — Add Prometheus as Grafana Datasource

Use Prometheus ELB:

```
http://<PROMETHEUS-ELB>:9090
```

Import dashboards to visualize node, cluster, and application metrics.

---

## Step 8 — Configure Alertmanager (Slack Integration)

Create a new channel on slack for monitoring #kubernetes-monitoring 

Create Slack webhook and store securely:

```bash
kubectl create secret generic alert-manager-webhook \
  -n monitoring \
  --from-literal=webhook-url=https://hooks.slack.com/services/XXXX/XXXX/XXXX
```

Apply AlertmanagerConfig manifest.

Create PrometheusRule to alert on:

1. CPU usage above 80% for 5 minutes
2. Pod restarts more than 3 times in 2 minutes
3. HTTP 5xx errors occurring 5 times within 5 minutes

```bash
kubectl apply -f prometheusrule.yml
```

---

## Step 9 — Test Prometheus Queries

Run on Prometheus bar:

```
kube_node_status_condition{condition="Ready", status="true"}
up
increase(kube_pod_container_status_restarts_total[10m])
```

---

## Step 10 — Trigger High CPU Load

```bash
kubectl run cpu-stress \
  --image=busybox \
  --restart=Never \
  -- /bin/sh -c "for i in 1 2 3 4; do while true; do :; done & done; wait"
```

---

## Step 11 — Verify Alerts

Wait a few minutes.

Check:

* Alertmanager UI → Alert firing
* Slack Channel → Notification received

---

## Step 12 — Visualize Metrics in Grafana

Open Grafana dashboards to view:

* Node utilization
* Pod health
* Application traffic
* Alert-triggered anomalies

---

# Project Completed

You have successfully:

* Built a Kubernetes cluster on AWS EKS
* Deployed a stateful production-style application
* Configured persistent storage with EBS CSI
* Exposed services using Traefik Ingress
* Installed full observability stack (Prometheus, Grafana, Alertmanager)
* Integrated Slack alerting for proactive monitoring
