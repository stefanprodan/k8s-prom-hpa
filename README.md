# k8s-prom-hpa

Kubernetes Horizontal Pod Autoscaler with Prometheus custom metrics

### Metrics Server

Deploy `metrics-server` in the `kube-system` namespace:

```bash
kubectl create \
    -f ./metrics-server
```

After one minute the `metric-server` will start reporting CPU and memory metrics for nodes and pods.

View nodes metrics:

```bash
kubectl get \
    --raw "/apis/metrics.k8s.io/v1beta1/nodes" | jq
```

View pods metrics:

```bash
kubectl get \
    --raw "/apis/metrics.k8s.io/v1beta1/pods" | jq
```

### Prometheus

Create the `monitoring` namespace:

```bash
kubectl create \
    -f ./namespaces.yaml
```

Deploy Prometheus v2 in the `monitoring` namespace:

```bash
kubectl create \
    -f ./prometheus
```

Generate the TLS certificates needed by the Prometheus adapter:

```bash
bash -c "cd custom-metrics-api && ./gencerts.sh"
```

Deploy the Prometheus custom metrics API adapter:

```bash
kubectl create \
    -f ./custom-metrics-api
```

List the custom metrics provided by Prometheus:

```bash
kubectl get \
    --raw "/apis/custom.metrics.k8s.io/v1beta1" | jq
```

Get the FS usage for all the pods in the `monitoring` namespace:

```bash
kubectl get \
    --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/monitoring/pods/*/fs_usage_bytes" | jq
```
