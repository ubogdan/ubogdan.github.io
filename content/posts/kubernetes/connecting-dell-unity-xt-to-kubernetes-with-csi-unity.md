---
title: "Connecting Dell Unity XT to Kubernetes with CSI-Unity on Bare-Metal"
date: 2025-11-22T19:52:02+02:00
tags: ["Kubernetes", "Helm", "Linux"]
categories: ["DevOps"]
description: "Setup Ubuntu node to pair with Dell Unity XT on Bare-Metal Kubernetes Cluster"
---

The Dell Container Storage Interface (CSI) Driver for Unity XT enables Kubernetes clusters to provision and manage storage volumes from Dell Unity XT arrays. This guide provides a comprehensive walkthrough for deploying CSI-Unity on a bare-metal Kubernetes cluster running Ubuntu 24.04, including multipath configuration and troubleshooting strategies.

### Prerequisites

- Kubernetes cluster (version 1.27+) running on Ubuntu 24.04
- Dell Unity XT storage array with:
    - Management IP address accessible from Kubernetes nodes
    - iSCSI or Fibre Channel connectivity configured
    - Storage pools created and available
- Administrative access to Kubernetes cluster and Unity XT array
- Helm 3.x installed
- kubectl configured with cluster admin privileges

## Architecture Overview

The CSI-Unity driver consists of two main components:

- **Controller Plugin**: Runs as a StatefulSet, handles volume provisioning, deletion, attachment, and snapshot operations
- **Node Plugin**: Runs as a DaemonSet on each node, manages volume mounting and multipath operations

Communication flows from Kubernetes through the CSI driver to the Dell Unity XT array via REST API for control operations and iSCSI/FC protocols for data path operations.

## Step 1: Configure Multipath on Ubuntu 24.04

Multipath is essential for high availability and load balancing across multiple storage paths. Configure multipathd before deploying the CSI driver.

### Install Multipath Tools

```bash
sudo apt update
sudo apt install -y multipath-tools sg3-utils
```

### Configure Multipathd

Create or modify the multipath configuration file:

```bash
sudo nano /etc/multipath.conf
```

Add the following configuration optimized for Dell Unity XT:

```conf
defaults {
    user_friendly_names     yes
    find_multipaths         yes
    polling_interval        5
    no_path_retry           queue
    dev_loss_tmo            30
    fast_io_fail_tmo        5
    rr_min_io               1000
    path_grouping_policy    group_by_prio
    path_selector           "service-time 0"
    features                "1 queue_if_no_path"
}

blacklist {
    devnode "^sd[a]$"
}

devices {
    device {
        vendor                  "DGC"
        product                 "VRAID"

        path_checker           tur
        hardware_handler       "1 alua"
        prio                    alua

        path_grouping_policy    group_by_prio
        path_selector           "service-time 0"
        failback                immediate
        no_path_retry           queue
        rr_min_io               1000
        dev_loss_tmo            30
        fast_io_fail_tmo        5
        features                "1 queue_if_no_path"
    }
}
```

### Enable and Start Multipath Service

```bash
sudo systemctl enable multipathd
sudo systemctl start multipathd
sudo systemctl status multipathd
```

### Verify Multipath Configuration

At this stage, if no storage is connected, the output will be minimal. Run the following command after connecting your Dell Unity XT storage to see the multipath devices:

```bash
sudo multipath -ll
mpatha (36006016022215c00d7202c69454b7b83) dm-0 DGC,VRAID
size=20G features='1 queue_if_no_path' hwhandler='1 alua' wp=rw
|-+- policy='service-time 0' prio=50 status=active
| |- 11:0:0:0 sdc 8:32 active ready running
| `- 13:0:1:0 sdf 8:80 active ready running
`-+- policy='service-time 0' prio=10 status=enabled
  |- 11:0:1:0 sdd 8:48 active ready running
  `- 13:0:0:0 sde 8:64 active ready running
```

An example output you may get with the default multipath configuration.
```bash
mpatha (36006016022215c00d7202c69454b7b83) dm-0 DGC,VRAID 
size=20G features='0' hwhandler='1 alua' wp=rw 
|-+- policy='service-time 0' prio=0 status=active 
| |- 11:0:0:0 sdc 8:32 failed faulty running 
| - 13:0:1:0 sdf 8:80 failed faulty running 
-+- policy='service-time 0' prio=0 status=enabled 
|- 11:0:1:0 sdd 8:48 failed faulty running 
 - 13:0:0:0 sde 8:64 failed faulty running
```
In this case you need to
* stop MultipathD
* hard reset the FC Sessions
* delete All Stale SCSI Devices
* Rescan Both HBAs Cleanly
* start MultipathD again.

```shell
systemctl stop multipathd
multipath -F

for h in 11 13; do
  echo 1 > /sys/class/fc_host/host$h/issue_lip
  sleep 3
done

for d in sdc sdd sde sdf; do
  echo 1 > /sys/block/$d/device/delete
done

## Confirm they are gone:
lsblk

for h in 11 13; do
  echo "- - -" > /sys/class/scsi_host/host$h/scan
done

## Confirm they are back:
lsblk

systemctl start multipathd
multipath -ll
```

## Step 2: Configure iSCSI (If Using iSCSI Protocol)

If your Dell Unity XT is configured for iSCSI connectivity, configure the iSCSI initiator on all Kubernetes nodes.

### Install iSCSI Initiator

The iSCSI initiator comes pre-installed on Ubuntu. If not, install it using:
```bash
sudo apt install -y open-iscsi
```

If you don't want to use iscsi, I recommend you need to rename the `/etc/iscsi/initiatorname.iscsi` otherwise the csi-unity driver will complain the iSCSI initiator is not healthy. 

### Configure iSCSI Initiator

Edit the iSCSI initiator configuration:

```bash
sudo nano /etc/iscsi/iscsid.conf
```

Update the following parameters:

```conf
node.startup = automatic
node.session.timeo.replacement_timeout = 120
node.conn[0].timeo.login_timeout = 15
node.conn[0].timeo.logout_timeout = 15
node.conn[0].timeo.noop_out_interval = 5
node.conn[0].timeo.noop_out_timeout = 5
node.session.err_timeo.abort_timeout = 15
node.session.err_timeo.lu_reset_timeout = 30
node.session.err_timeo.tgt_reset_timeout = 30
node.session.iscsi.InitialR2T = No
node.session.iscsi.ImmediateData = Yes
node.session.iscsi.FirstBurstLength = 262144
node.session.iscsi.MaxBurstLength = 16776192
node.conn[0].iscsi.MaxRecvDataSegmentLength = 262144
```

### Set iSCSI Initiator Name

Each node should have a unique initiator name:

```bash
sudo nano /etc/iscsi/initiatorname.iscsi
```

Example format:

```
InitiatorName=iqn.1993-08.org.debian:01:node1
```

### Enable and Start iSCSI Service

```bash
sudo systemctl enable iscsid.socket
```

### Discover and Login to Unity XT iSCSI Targets

Replace `<UNITY_ISCSI_IP>` with your Unity XT iSCSI portal IP:

```bash
sudo iscsiadm -m discovery -t sendtargets -p <UNITY_ISCSI_IP>
sudo iscsiadm -m node --login
```

Verify active sessions:

```bash
sudo iscsiadm -m session
```

## Step 3: Prepare Kubernetes Cluster

### Create Namespace for CSI Driver

```bash
kubectl create namespace unity
```

### Label Nodes for CSI Driver

If you want to run the CSI node plugin on specific nodes only:

```bash
kubectl label nodes <node-name> unity-storage=enabled
```

Otherwise, the DaemonSet will run on all nodes by default.

## Step 4: Create Unity XT Connection Secret

The CSI driver requires credentials to communicate with the Dell Unity XT array.

### Gather Unity XT Information

You'll need:
- Unity XT management IP address
- Username with appropriate permissions (e.g., `admin`)
- Password
- Storage array ID (optional but recommended)

### Create Secret Configuration

Create a file named `secret.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: csi-unity-certs-0
  namespace: unity
type: Opaque
data:
  cert-0: ""
--- 
apiVersion: v1
kind: Secret
metadata:
  name: unity-creds
  namespace: unity
type: Opaque
stringData:
  config: |
    storageArrayList:
      - arrayId: "APM00123456789"
        username: "admin"
        password: "Password123!"
        endpoint: "https://10.0.0.100"
        skipCertificateValidation: true
        isDefault: true
```

**Important Security Notes:**
- In production, use a dedicated service account instead of `admin`
- Consider using Kubernetes secrets management solutions like Sealed Secrets or External Secrets Operator
- Set `skipCertificateValidation: false` if you have proper SSL certificates configured

### Apply the Secret

```bash
kubectl apply -f secret.yaml
```

Verify the secret:

```bash
kubectl get secret unity-creds -n unity
```

## Step 5: Deploy CSI-Unity Driver with Helm

### Add Dell CSI Helm Repository

```bash
helm repo add dell https://dell.github.io/helm-charts
helm repo update
```

### Download and Customize Values

Download the default values file for customization:

```bash
helm show values dell/csi-unity > unity-values.yaml
```

### Configure Values File

Edit `unity-values.yaml` with your specific requirements. Key configurations:

```yaml
# Image settings
images:
  driverRepository: dellemc/csi-unity
  
# Controller settings
controller:
  controllerCount: 2
  volumeNamePrefix: "csivol"
  
# Node settings
node:
  nodeSelector: { "kubernetes.io/os": "linux" }
  tolerations: []
  
# Snapshot settings
snapshot:
  enabled: true
  
# Monitoring
monitor:
  enabled: true
```

### Install the CSI Driver

```bash
helm install csi-unity dell/csi-unity \
  --namespace unity \
  --values unity-values.yaml
```

### Verify Installation

Check the deployment status:

```bash
kubectl get all -n unity
```

Expected output should show:
- StatefulSet for controller (2 replicas)
- DaemonSet for node plugins
- Services for the driver

Check pod status:

```bash
kubectl get pods -n unity -w
```

Wait until all pods are in `Running` state.

### Verify CSI Driver Registration

```bash
kubectl get csidrivers
```

You should see `csi-unity.dellemc.com` listed.

### Check Storage Classes

```bash
kubectl get storageclass
```

You should see the storage classes defined in your values file.

## Step 6: Test Storage Provisioning
### Create a Storage Class
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: unity-fc-sc
provisioner: csi-unity.dellemc.com
parameters:
  protocol: FC
  pool: pool_1
  storagePool: pool_1
  arrayId: "APM00123456789"
  tieringPolicy: HighestAvailable
  thinProvisioned: "true"
  csi.storage.k8s.io/fstype: ext4
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: Immediate
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: unity-fc-iscsi
provisioner: csi-unity.dellemc.com
parameters:
  protocol: iSCSI
  pool: pool_1
  storagePool: pool_1
  arrayId: "APM00123456789"
  tieringPolicy: HighestAvailable
  thinProvisioned: "true"
  csi.storage.k8s.io/fstype: ext4
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: Immediate
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: unity-fc-nfs
provisioner: csi-unity.dellemc.com
parameters:
  protocol: NFS
  pool: pool_1
  storagePool: pool_1
  nasServer: "NasServer1"
  tieringPolicy: HighestAvailable
  thinProvisioned: "true"
  csi.storage.k8s.io/fstype: ext4
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: Immediate
```

Note: For protocol FC and ISCSI the arrayId value should match an arrayID from the secret.  

### Create a Test PVC

Create a file named `test-pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-unity-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: unity-fc-sc
  resources:
    requests:
      storage: 5Gi
```

Apply the PVC:

```bash
kubectl apply -f test-pvc.yaml
```

### Verify PVC Status

```bash
kubectl get pvc test-unity-pvc -n default -w
```

The PVC should transition from `Pending` to `Bound` within a few seconds.

### Check PV Creation

```bash
kubectl get pv
```

You should see a dynamically provisioned PV bound to your PVC.

### Create a Test Pod

Create a file named `test-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-unity-pod
  namespace: default
spec:
  containers:
  - name: test-container
    image: nginx:latest
    volumeMounts:
    - name: unity-volume
      mountPath: /data
    command: ["/bin/sh"]
    args: ["-c", "echo 'Hello from Unity XT Storage' > /data/test.txt && tail -f /dev/null"]
  volumes:
  - name: unity-volume
    persistentVolumeClaim:
      claimName: test-unity-pvc
```

Apply the pod:

```bash
kubectl apply -f test-pod.yaml
```

### Verify Pod and Volume Mount

```bash
kubectl get pod test-unity-pod -n default
kubectl exec -it test-unity-pod -n default -- df -h /data
kubectl exec -it test-unity-pod -n default -- cat /data/test.txt
```

## Step 7: Advanced Configuration

### Volume Snapshots

Enable volume snapshots for backup and cloning capabilities.

#### Create VolumeSnapshotClass

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: unity-snapclass
driver: csi-unity.dellemc.com
deletionPolicy: Delete
```

#### Create a Snapshot

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: test-unity-snapshot
  namespace: default
spec:
  volumeSnapshotClassName: unity-snapclass
  source:
    persistentVolumeClaimName: test-unity-pvc
```

#### Restore from Snapshot

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: restored-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: unity-iscsi
  dataSource:
    name: test-unity-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  resources:
    requests:
      storage: 5Gi
```

### Volume Cloning

Clone an existing PVC directly:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cloned-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: unity-iscsi
  dataSource:
    name: test-unity-pvc
    kind: PersistentVolumeClaim
  resources:
    requests:
      storage: 5Gi
```

### Volume Expansion

To expand a volume, edit the PVC:

```bash
kubectl edit pvc test-unity-pvc -n default
```

Increase the `spec.resources.requests.storage` value. The CSI driver will automatically resize the volume.

## Debugging and Troubleshooting

### Common Issues and Solutions

#### Issue 1: Pods Stuck in ContainerCreating

**Symptoms:**
```bash
kubectl describe pod <pod-name> -n unity
```
Shows: `FailedMount: MountVolume.SetUp failed`

**Investigation Steps:**

1. Check CSI node plugin logs:
```bash
kubectl logs -n unity -l app=csi-unity-node -c driver
```

2. Check for multipath issues on the node:
```bash
sudo multipath -ll
sudo multipath -v3
```

3. Verify iSCSI sessions (for iSCSI):
```bash
sudo iscsiadm -m session
```

**Common Solutions:**
- Restart multipathd: `sudo systemctl restart multipathd`
- Rescan SCSI bus: `sudo rescan-scsi-bus.sh`
- Check node plugin tolerations and node selectors

#### Issue 2: PVC Stuck in Pending

**Symptoms:**
```bash
kubectl get pvc
```
Shows: Status remains `Pending`

**Investigation Steps:**

1. Describe the PVC:
```bash
kubectl describe pvc <pvc-name>
```

2. Check controller logs:
```bash
kubectl logs -n unity -l app=csi-unity-controller -c driver
```

3. Verify storage class exists:
```bash
kubectl get storageclass
```

**Common Solutions:**
- Verify Unity XT credentials in secret
- Check storage pool availability on Unity XT
- Ensure CSI controller pods are running
- Verify network connectivity to Unity XT management IP
- Verify cs-unity-node-xxx running on the node the pods claiming a persistent volume was scheduled, the `driver` container of `cs-unity-node-xxx` pod should provide more details about the issue.

#### Issue 3: Authentication Failures

**Symptoms:**
Driver logs show authentication errors:
```
Error: authentication failed for array
```

**Investigation Steps:**

1. Verify secret contents:
```bash
kubectl get secret unity-creds -n unity -o yaml
```

2. Decode and check credentials:
```bash
kubectl get secret unity-creds -n unity -o jsonpath='{.data.config}' | base64 -d
```

3. Test Unity XT API access:
```bash
curl -k -u admin:password https://<unity-ip>/api/types/system/instances
```

**Solutions:**
- Update secret with correct credentials
- Verify user has appropriate permissions on Unity XT
- Check Unity XT management network connectivity

#### Issue 4: Multipath Not Working

**Symptoms:**
Only single path visible, no redundancy

**Investigation Steps:**

1. Check multipath status:
```bash
sudo multipath -ll
sudo systemctl status multipathd
```

2. Verify all paths are discovered:
```bash
sudo multipath -v3
lsblk
```

3. Check multipath configuration:
```bash
sudo multipathd show config
```

**Solutions:**
- Verify all storage network interfaces are up
- Check iSCSI sessions to all portals
- Review blacklist configuration
- Restart multipathd service

### Useful Debugging Commands

#### Check CSI Driver Status

```bash
# List all CSI-related resources
kubectl get all -n unity

# Check driver registration
kubectl get csidrivers

# View CSI node info
kubectl get csinodes

# Check volume attachments
kubectl get volumeattachment
```

#### Examine Logs

```bash
# Controller logs
kubectl logs -n unity -l app=csi-unity-controller -c driver --tail=100 -f

# Node plugin logs
kubectl logs -n unity -l app=csi-unity-node -c driver --tail=100 -f

# Provisioner sidecar logs
kubectl logs -n unity -l app=csi-unity-controller -c provisioner --tail=100 -f

# Attacher sidecar logs
kubectl logs -n unity -l app=csi-unity-controller -c attacher --tail=100 -f
```

#### Node-Level Debugging

```bash
# Check iSCSI sessions
sudo iscsiadm -m session -P 3

# Check multipath devices
sudo multipath -ll
sudo dmsetup ls --tree

# Check block devices
lsblk
lsscsi

# Check for errors in system logs
sudo journalctl -u multipathd -f
sudo journalctl -u iscsid -f
```

#### Performance Monitoring

```bash
# Check I/O statistics
iostat -x 2

# Monitor multipath path failures
sudo multipathd show paths

# Check for device errors
dmesg | grep -i error
```

### Enable Debug Logging

To increase log verbosity for the CSI driver, update the Helm values:

```yaml
logLevel: "debug"
```

Upgrade the Helm release:

```bash
helm upgrade csi-unity dell/csi-unity \
  --namespace unity \
  --values unity-values.yaml
```

### Known Limitations

1. **Protocol Switching**: Once a PVC is created with a protocol (iSCSI/FC/NFS), it cannot be changed
2. **Raw Block Volumes**: Supported but require specific pod configurations
3. **ReadWriteMany**: Only supported with NFS protocol
4. **Topology**: Requires careful configuration in multi-zone clusters

## Monitoring and Maintenance

### Health Checks

Create a monitoring script to regularly check CSI driver health:

```bash
#!/bin/bash

echo "Checking CSI Unity Driver Health..."

# Check controller pods
CONTROLLER_STATUS=$(kubectl get pods -n unity -l app=csi-unity-controller -o jsonpath='{.items[*].status.phase}')
echo "Controller Status: $CONTROLLER_STATUS"

# Check node pods
NODE_COUNT=$(kubectl get pods -n unity -l app=csi-unity-node --no-headers | wc -l)
NODE_READY=$(kubectl get pods -n unity -l app=csi-unity-node -o jsonpath='{.items[*].status.phase}' | grep -o "Running" | wc -l)
echo "Node Pods: $NODE_READY/$NODE_COUNT ready"

# Check PVC status
PENDING_PVCS=$(kubectl get pvc -A -o json | jq -r '.items[] | select(.status.phase=="Pending") | "\(.metadata.namespace)/\(.metadata.name)"')
if [ -z "$PENDING_PVCS" ]; then
    echo "All PVCs are bound"
else
    echo "Pending PVCs:"
    echo "$PENDING_PVCS"
fi
```

### Regular Maintenance Tasks

1. **Update CSI Driver**: Regularly check for updates
```bash
helm repo update
helm search repo dell/csi-unity --versions
helm upgrade csi-unity dell/csi-unity --namespace unity --values unity-values.yaml
```

2. **Rotate Credentials**: Update Unity XT credentials periodically
```bash
kubectl delete secret unity-creds -n unity
kubectl apply -f secret.yaml
kubectl rollout restart statefulset -n unity
kubectl rollout restart daemonset -n unity
```

3. **Monitor Capacity**: Track storage usage
```bash
kubectl get pv -o json | jq -r '.items[] | "\(.spec.capacity.storage) - \(.spec.claimRef.name)"'
```

## Production Best Practices

### High Availability

1. **Multiple Controller Replicas**: Run at least 2 controller replicas
2. **Spread Across Nodes**: Use pod anti-affinity
3. **Resource Limits**: Set appropriate CPU and memory limits
4. **Health Probes**: Configure liveness and readiness probes

### Security Hardening

1. **Use Service Accounts**: Create dedicated Unity XT users with minimal permissions
2. **Enable TLS**: Configure proper SSL certificates, disable `skipCertificateValidation`
3. **Network Policies**: Restrict access to CSI pods
4. **Secrets Management**: Use external secrets management solutions
5. **RBAC**: Apply principle of least privilege

### Performance Optimization

1. **Storage Network**: Use dedicated VLANs for storage traffic
2. **Multipath Configuration**: Tune `rr_min_io` based on workload
3. **Queue Depth**: Adjust iSCSI queue depth for high-throughput workloads
4. **Storage Pools**: Use SSD-backed pools for latency-sensitive applications

### Backup and Disaster Recovery

1. **Snapshot Schedules**: Implement automated snapshot policies
2. **Replication**: Configure Unity XT replication for DR
3. **Backup PVC Data**: Use Velero or similar tools for cluster-level backups
4. **Document Configuration**: Maintain documentation of storage configurations

## Conclusion

Deploying Dell Unity XT CSI driver on bare-metal Kubernetes with Ubuntu 24.04 provides enterprise-grade storage capabilities with features like dynamic provisioning, snapshots, and cloning. Proper multipath configuration ensures high availability and optimal performance.

Key takeaways:
- Multipath configuration is critical for production deployments
- Thorough testing with various workload patterns is essential
- Regular monitoring and maintenance ensure long-term stability
- Understanding the debugging tools saves time during incidents

For additional support and updates, refer to:
- [Dell CSI Driver Documentation](https://dell.github.io/csm-docs/)
- [GitHub Repository](https://github.com/dell/csi-unity)
- Dell Support Portal
