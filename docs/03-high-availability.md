# 03. High Availability Load Balancers

## 1. Objective
This part of the project aims to improve the high availability of the Kubernetes cluster by eliminating the Single Point of Failure (SPOF) represented by a single Load Balancer.

The architecture relies on two Load Balancers using **HAProxy** and **Keepalived**, sharing a Virtual IP (VIP) address. This provides a single, stable endpoint to access the Kubernetes API.
Thus, if the primary Load Balancer becomes unavailable, the secondary one will automatically take over the virtual address.

## 2. Architecture
The infrastructure consists of the following components:

| Component | IP Address | Role |
| :--- | :--- | :--- |
| **lb1** | `192.168.56.20` | Primary Load Balancer |
| **lb2** | `192.168.56.30` | Secondary Load Balancer |
| **VIP** | `192.168.56.10` | Single Endpoint for the Kubernetes Cluster |
| **master1** | `192.168.56.11` | Control Plane |
| **master2** | `192.168.56.12` | Control Plane |
| **master3** | `192.168.56.13` | Control Plane |

Both Load Balancers operate on the VirtualBox private network. The Control Planes remain accessible via the endpoint:
`192.168.56.10:6443`

*Note: This virtual address is also used as the `controlPlaneEndpoint` for `kubeadm`.*

## 3. Role of HAProxy
HAProxy ensures the distribution of TCP connections to the three Kubernetes API Servers.
It listens on port `6443` and forwards the connections to the available Control Planes.

The servers configured in the backend are:
- **master1**: `192.168.56.11:6443`
- **master2**: `192.168.56.12:6443`
- **master3**: `192.168.56.13:6443`

The load balancing is performed using the `roundrobin` algorithm, along with TCP availability checks.
Both Load Balancers use the exact same HAProxy configuration so that either one can take over seamlessly.

## 4. Role of Keepalived and VRRP
Keepalived manages the assignment of the Virtual IP address between the two Load Balancers.
It relies on the VRRP (Virtual Router Redundancy Protocol) to orchestrate the failover.

The configuration uses two roles:
- **MASTER**: `lb1`, with a priority of `150`.
- **BACKUP**: `lb2`, with a priority of `100`.

The VRRP protocol is configured in unicast mode to allow both machines to communicate directly over the private network.
A tracking mechanism also monitors the state of the HAProxy service. If HAProxy becomes unavailable or crashes, the priority of the affected Load Balancer is dynamically reduced to trigger a failover to the other machine.

## 5. Failover Operation

**During normal operation:**
1. `lb1` holds the virtual address `192.168.56.10`.
2. Clients access the Kubernetes API via `192.168.56.10:6443`.
3. HAProxy forwards the connections to the available API Servers.
4. `lb2` remains on standby and monitors the state of the primary Load Balancer.

**If the primary Load Balancer becomes unavailable:**
1. Keepalived detects the loss of VRRP announcements or the degradation of the monitored HAProxy service.
2. `lb2` takes over and claims the virtual address.
3. New connections continue to flow through `192.168.56.10:6443`.
4. Clients keep using the same endpoint, without needing to modify their configuration.

*Note: The failover may cause a brief interruption for existing connections, which may need to be re-established. The VIP should normally be present on only one Load Balancer at a time.*

## 6. Service Verification

On each Load Balancer, check the status of HAProxy:
```bash
sudo systemctl status haproxy
```

Check the status of Keepalived:
```bash
sudo systemctl status keepalived
```

Display the IP addresses of the network interfaces:
```bash
ip -o addr show
```

To verify the presence of the VIP:
```bash
ip -o addr show | grep '192.168.56.10'
```
*This command should normally return the VIP only on the currently active Load Balancer.*

Verify connectivity to the Kubernetes API port from a machine that has access to the private network:
```bash
nc -zv 192.168.56.10 6443
```

Finally, verify the status of the cluster from a master node:
```bash
kubectl get nodes -o wide
```

## 7. Failover Testing

To test the high availability mechanism, temporarily stop Keepalived on the primary Load Balancer (`lb1`):
```bash
sudo systemctl stop keepalived
```

Then, verify that the VIP has successfully migrated to `lb2`:
```bash
ip -o addr show | grep '192.168.56.10'
```

Test the access to the Kubernetes API again:
```bash
nc -zv 192.168.56.10 6443
kubectl get nodes -o wide
```
If the configuration works correctly, `lb2` takes over the VIP and the Kubernetes API remains accessible via the same endpoint.

At the end of the test, restart Keepalived on the first Load Balancer:
```bash
sudo systemctl start keepalived
```
Check the state of both Load Balancers again to ensure the VIP fails back (or stays stable, depending on your `preempt` settings) as expected.

## 8. Expected Result
This extension successfully removes the single Load Balancer as a point of failure in the architecture.

The combination of HAProxy and Keepalived provides:
- Load Balancer redundancy.
- Automatic failover of the Virtual IP address.
- A stable endpoint for accessing the Kubernetes API.
- Traffic distribution across the three Control Planes.
- The ability to safely test the infrastructure's behavior during a primary Load Balancer outage.

This architecture represents a fundamental step toward a highly available Kubernetes infrastructure, deployed locally with Vagrant and VirtualBox.