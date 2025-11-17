# O-RAN RIC Platform - Performance Test Report

**Author:** 蔡秀吉 (thc1006)
**Date:** 2025-11-17 21:39:14
**Test Duration:** 300 seconds

---

## Test Environment

### Kubernetes Cluster
```
Client Version: v1.34.1
Kustomize Version: v5.7.1
Server Version: v1.28.5+k3s1
```

### Node Information
```
NAME      STATUS   ROLES                  AGE   VERSION        INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                       KERNEL-VERSION        CONTAINER-RUNTIME
thc1006   Ready    control-plane,master   32h   v1.28.5+k3s1   31.41.34.19   <none>        Debian GNU/Linux 13 (trixie)   6.12.48+deb13-amd64   containerd://1.7.11-k3s2
```

### Node Resources
```
NAME      CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)   
thc1006   1055m        3%       7174Mi          14%         
```

## Test 1: Resource Utilization Analysis

### Platform Pods (ricplt)
```
NAME                                                       CPU(cores)   MEMORY(bytes)   
oran-grafana-f6bb8ff8f-c6bdc                               4m           108Mi           
r4-infrastructure-prometheus-alertmanager-fb95778b-48qvs   2m           21Mi            
r4-infrastructure-prometheus-server-6c4cbf94d4-z9h8k       15m          193Mi           
```

### xApp Pods (ricxapp)
```
NAME                                  CPU(cores)   MEMORY(bytes)   
e2-simulator-54f6cfd7b4-h4kqv         3m           15Mi            
federated-learning-58fc88ffc6-lhc6m   2m           469Mi           
kpimon-54486974b6-gxmfw               3m           134Mi           
qoe-predictor-55b75b5f8c-l6bwg        2m           294Mi           
ran-control-5448ff8945-z5m6c          2m           50Mi            
traffic-steering-664d55cdb5-2zsbl     2m           38Mi            
```

### Resource Configuration Analysis

#### Platform Components
```
r4-infrastructure-prometheus-server-6c4cbf94d4-z9h8k
          Requests: CPU=500m
                   MEM=1Gi
          Limits:   CPU=1
                   MEM=2Gi
        
r4-infrastructure-prometheus-alertmanager-fb95778b-48qvs
          Requests: CPU=50m
                   MEM=64Mi
          Limits:   CPU=100m
                   MEM=128Mi
        
oran-grafana-f6bb8ff8f-c6bdc
          Requests: CPU=250m
                   MEM=256Mi
          Limits:   CPU=500m
                   MEM=512Mi
        
```

### CPU Throttling Analysis

Pods experiencing CPU throttling in the last 5 minutes:
```
