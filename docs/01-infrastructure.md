# 1. Infrastructure Setup

## Objective

The objective of this lab is to build a virtual infrastructure for a Kubernetes high-availability environment using Vagrant and VirtualBox. The entire environment is automatically provisioned using shell scripts.

## Technologies

* **VirtualBox:** virtual machine hypervisor.
* **Vagrant:** virtual machine provisioning and lifecycle management.
* **Debian Bookworm:** operating system used by the virtual machines.
* **Kubernetes (kubeadm):** container orchestration platform.
* **Shell Scripting:** automated system preparation and software installation.

## Virtual Machines

| Hostname | IP Address | Role | Provisioning Script |
| ----- | ----- | ----- | ----- |
| `lb` | 192.168.56.20 | Primary load balancer | `haproxy.sh` |
| `lb2` | 192.168.56.30 | Secondary load balancer | `haproxy.sh` |
| `master1-3` | 192.168.56.11-13 | Kubernetes control plane | `bootstrap.sh` |
| `worker1-2` | 192.168.56.21-22 | Kubernetes worker | `bootstrap.sh` |
| `monitoring` | 192.168.56.40 | Prometheus and Grafana | *None (Manual or future script)* |

## Automated Provisioning

The infrastructure is defined in a `Vagrantfile`. Vagrant automatically applies specific shell scripts to configure each machine type during creation.

### 1. The Vagrantfile
The `Vagrantfile` defines the specifications (Memory: `512MB` for LBs, `2048MB` for Masters/Workers/Monitoring; CPUs) and assigns private IP addresses. It maps the virtual machines to their respective provisioning scripts:

```ruby
Vagrant.configure("2") do |config|
    config.vm.box = "debian/bookworm64"
    # ... (VM definitions for lb, lb2, monitoring, master1-3, worker1-2)
    # Example for a worker node:
    # worker.vm.provision "shell", path: "../scripts/bootstrap.sh"
end
```

### 2. Node Preparation (`bootstrap.sh`)
Used by all Kubernetes nodes (masters and workers). This script automates the standard Kubernetes prerequisites:
* Updates the Debian system.
* Disables Swap (a strict Kubernetes requirement).
* Loads required kernel modules (`overlay`, `br_netfilter`) and applies `sysctl` network parameters.
* Installs and configures the container runtime (**Containerd**).
* Adds the official Kubernetes repository.
* Installs cluster components: `kubelet`, `kubeadm`, and `kubectl`.
* Configures local DNS resolution (`/etc/hosts`).

### 3. Load Balancer Setup (`haproxy.sh`)
Used by `lb` and `lb2`. This script sets up the high availability layer:
* Installs HAProxy and Keepalived.
* Detects local network interfaces dynamically.
* Generates a TCP Load Balancing configuration for HAProxy to route traffic to the Kubernetes API.
* Generates service monitoring scripts for HAProxy.
* Configures Keepalived to manage the Virtual IP (VIP).
* Restarts and enables all services.

## Deployment

Start the virtual machines and trigger the automated provisioning:

```bash
vagrant up
```

Check their status:

```bash
vagrant status
```

Connect to a virtual machine:

```bash
vagrant ssh lb
```

## Validation

Before proceeding to cluster initialization, verify that the virtual machines are running, reachable, and that the provisioning scripts (`bootstrap.sh` and `haproxy.sh`) have executed successfully by checking installed versions (e.g., `kubeadm version`, `haproxy -v`).

Next steps will involve initializing the Kubernetes cluster, configuring the load balancers, and setting up monitoring with Prometheus and Grafana.