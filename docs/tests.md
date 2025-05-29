# Test Cases

This document outlines the test cases for verifying the functionality of the DigitalOcean CSI driver implementation.

## Prerequisites

Before running tests, ensure:
1. The cluster is running and accessible
2. The CSI driver is installed and running
3. The storage class is configured
4. You have kubectl configured with the correct context

## Basic Functionality Tests

### 1. Storage Class Verification

```bash
# Test Case: Verify storage class exists and is default
kubectl get storageclass
kubectl describe storageclass do-block-storage

# Expected Output:
# - do-block-storage should be listed
# - storageclass.kubernetes.io/is-default-class: "true" should be present
# - provisioner should be dobs.csi.digitalocean.com
```

### 2. PVC Creation and Binding

```bash
# Test Case: Create and verify PVC
kubectl apply -f k8s/test-pvc.yaml
kubectl get pvc test-pvc

# Expected Output:
# - PVC should be in Bound state
# - Volume should be provisioned
# - Storage class should be do-block-storage
```

### 3. Pod with PVC

```bash
# Test Case: Verify pod can write to PVC
kubectl get pod test-pod
kubectl exec test-pod -- cat /data/test.txt

# Expected Output:
# - Pod should be in Running state
# - /data/test.txt should contain "Hello from PVC"
```

## Volume Operations Tests

### 1. Volume Expansion

```bash
# Test Case: Expand PVC size
kubectl patch pvc test-pvc -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'
kubectl get pvc test-pvc

# Expected Output:
# - PVC should show new size
# - Volume should be expanded
```

### 2. Volume Snapshot

```bash
# Test Case: Create and verify snapshot
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: test-snapshot
spec:
  volumeSnapshotClassName: do-block-storage-snapshot
  source:
    persistentVolumeClaimName: test-pvc
EOF

kubectl get volumesnapshot test-snapshot

# Expected Output:
# - Snapshot should be created
# - Status should be ReadyToUse
```

### 3. Restore from Snapshot

```bash
# Test Case: Restore PVC from snapshot
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: restored-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: do-block-storage
  dataSource:
    name: test-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF

kubectl get pvc restored-pvc

# Expected Output:
# - New PVC should be created
# - Should be bound to a new volume
# - Should contain data from snapshot
```

## Error Handling Tests

### 1. Invalid Storage Class

```bash
# Test Case: Attempt to create PVC with invalid storage class
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: invalid-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: non-existent
EOF

kubectl get pvc invalid-pvc

# Expected Output:
# - PVC should be in Pending state
# - Events should show storage class not found
```

### 2. Insufficient Storage

```bash
# Test Case: Attempt to create PVC with invalid size
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: invalid-size-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 999999Gi
  storageClassName: do-block-storage
EOF

kubectl get pvc invalid-size-pvc

# Expected Output:
# - PVC should be in Pending state
# - Events should show storage quota exceeded
```

## Cleanup Tests

### 1. PVC Deletion

```bash
# Test Case: Delete PVC and verify cleanup
kubectl delete pvc test-pvc
kubectl get pvc test-pvc

# Expected Output:
# - PVC should be deleted
# - Associated volume should be deleted
```

### 2. Snapshot Deletion

```bash
# Test Case: Delete snapshot and verify cleanup
kubectl delete volumesnapshot test-snapshot
kubectl get volumesnapshot test-snapshot

# Expected Output:
# - Snapshot should be deleted
# - Associated snapshot content should be deleted
```

## Performance Tests

### 1. Volume Creation Time

```bash
# Test Case: Measure PVC creation time
time kubectl apply -f k8s/test-pvc.yaml

# Expected Output:
# - PVC should be created within 30 seconds
```

### 2. Snapshot Creation Time

```bash
# Test Case: Measure snapshot creation time
time kubectl apply -f k8s/test-snapshot.yaml

# Expected Output:
# - Snapshot should be created within 60 seconds
```

## Test Results

After running all tests, document the results:

1. Basic Functionality:
   - [ ] Storage class verification
   - [ ] PVC creation and binding
   - [ ] Pod with PVC

2. Volume Operations:
   - [ ] Volume expansion
   - [ ] Volume snapshot
   - [ ] Restore from snapshot

3. Error Handling:
   - [ ] Invalid storage class
   - [ ] Insufficient storage

4. Cleanup:
   - [ ] PVC deletion
   - [ ] Snapshot deletion

5. Performance:
   - [ ] Volume creation time
   - [ ] Snapshot creation time

## Notes

- All tests should be run in a clean environment
- Document any failures or unexpected behavior
- Update test cases as new features are added
- Consider adding automated test scripts 