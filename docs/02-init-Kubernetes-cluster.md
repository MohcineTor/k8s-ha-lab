# 2. Initializing the Kubernetes Cluster and Installing Calico

This document describes the process of initializing the first master node (Control Plane) of the Kubernetes cluster and deploying the Calico network plugin (CNI).

This step is fully automated by the `init-control-plane.sh` script provided in this repository.

## ⚠️ Important Warning: VirtualBox / Vagrant Environments

If you are using Vagrant with VirtualBox to build this cluster, your virtual machines will have a **NAT network interface (usually `10.0.2.15`)** by default, in addition to your private network (e.g., `192.168.56.x`).

**The Problem:**
By default, Kubernetes might select this NAT interface. If the API Server or Kubelet binds to the `10.0.2.15` IP, the nodes will not be able to communicate with each other and will remain stuck in the `NotReady` state.

**The Solution:**

1. **On the first master (`master1`)**: Our `kubeadm-config.yaml` file already forces the use of the correct IP for the API Server. The parameter `KUBELET_EXTRA_ARGS=--node-ip=<PRIVATE_IP>` must also be present on every node (configured via `/etc/default/kubelet`).

2. **For future master nodes**: When adding new master nodes to the cluster, it is mandatory to force the private IP (e.g., `192.168.56.11`) to prevent them from using the NAT IP. The following parameter must be appended to the join command:

   ```bash
   --apiserver-advertise-address=<NEW_MASTER_PRIVATE_IP>
   ```

## How the `init-control-plane.sh` Script Works

The initialization script automatically performs the following actions on your `master1` node:

1. **Pre-flight Checks:** Verifies that the script is running on the first master node, ensures the cluster is not already initialized, and confirms that the `containerd` service is active.

2. **Configuration Adaptation:** Detects the installed Kubernetes version and dynamically updates the `kubeadm-config.yaml` file to match.

3. **Initialization (kubeadm init):** Bootstraps the Control Plane and uploads the certificates to prepare the cluster for High Availability (HA).

4. **Administrator Access Configuration:** Copies the credentials so the local user can execute `kubectl` commands.

5. **Calico Network Deployment:**
   * Installs the Tigera Operator.
   * Waits for the Custom Resource Definitions (CRDs) to become available.
   * Deploys the Calico network specifically configured for our Pod CIDR (`10.244.0.0/16`).

6. **Join Scripts Generation:** Creates two ready-to-use files in the `/home/vagrant/join-scripts/` directory:
   * `worker.sh`: Used to join worker nodes to the cluster.
   * `control-plane.sh`: Used to join additional master nodes to the cluster.

## How to Execute This Step

1. Connect to your first master node (e.g., via `vagrant ssh master1`).

2. Ensure that the `kubeadm-config.yaml` file is correctly located in the `../scripts/` directory relative to the script's location.

3. Run the script with administrator privileges:

   ```bash
   sudo ./init-control-plane.sh
   ```

## Next Steps

Once the script finishes successfully, you will see a success message indicating that the cluster is initialized.

You can then retrieve the generated `worker.sh` and `control-plane.sh` files from the `/home/vagrant/join-scripts/` directory, transfer them to your other machines, and execute them to assemble your cluster.

You can also verify the cluster status by running the following command:

```bash
kubectl get nodes
```

In the scripts folder, I have provided a script that performs end-to-end tests to verify that all nodes are ready and that Calico is working properly.

Copy the script to the master1 node and run it to ensure that everything is working as expected:

```bash
sudo ./scripts/verify.sh
```