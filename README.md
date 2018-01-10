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

### Auto Scaling

Create `podinfo` NodePort service and deployment in the `default` namespace:

```bash
kubectl create \
    -f ./podinfo/podinfo-svc.yaml,podinfo-dep.yaml
```

The `podinfo` app exposes a custom metric named `http_requests_total`. 
The Prometheus adapter removes the `_total` suffix and marks the metric as a counter metric.

Get the total requests per second from the custom metrics API:

```bash
kubectl get \
    --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/http_requests" | jq
```
```json
{
  "kind": "MetricValueList",
  "apiVersion": "custom.metrics.k8s.io/v1beta1",
  "metadata": {
    "selfLink": "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/%2A/http_requests"
  },
  "items": [
    {
      "describedObject": {
        "kind": "Pod",
        "namespace": "default",
        "name": "podinfo-6b86c8ccc9-kv5g9",
        "apiVersion": "/__internal"
      },
      "metricName": "http_requests",
      "timestamp": "2018-01-10T16:49:07Z",
      "value": "901m"
    },
    {
      "describedObject": {
        "kind": "Pod",
        "namespace": "default",
        "name": "podinfo-6b86c8ccc9-nm7bl",
        "apiVersion": "/__internal"
      },
      "metricName": "http_requests",
      "timestamp": "2018-01-10T16:49:07Z",
      "value": "898m"
    }
  ]
}
```

If you're wandering what `m` represents it's `milli-units`, so the `901m` means 901 milli-requests.

Let's create a HPA that will scale up the `podinfo` deployment if the number of requests goes over 10 per second:

```yaml
apiVersion: autoscaling/v2beta1
kind: HorizontalPodAutoscaler
metadata:
  name: podinfo
spec:
  scaleTargetRef:
    apiVersion: extensions/v1beta1
    kind: Deployment
    name: podinfo
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Pods
    pods:
      metricName: http_requests
      targetAverageValue: 10
```

Create the hpa in the `default` namespace:

```bash
kubectl create \
    -f ./podinfo/podinfo-svc.yaml,podinfo-hpa-custom.yaml
```

After a couple of seconds the HPA will fetch the `http_requests` value from the metrics API:

```bash
kubectl get hpa

NAME      REFERENCE            TARGETS     MINPODS   MAXPODS   REPLICAS   AGE
podinfo   Deployment/podinfo   899m / 10   2         10        2          1m
```

Let's hit the `podinfo` service with 25 requests per second:

```bash
#install hey
go get -u github.com/rakyll/hey

#do 10K requests rate limited at 25 QPS
hey -n 10000 -q 5 -c 5 http://<K8S-IP>:31198/healthz
```

After a couple of minutes the HPA will start to scale up the deployment:

```
kubectl describe hpa

Name:                       podinfo
Namespace:                  default
Reference:                  Deployment/podinfo
Metrics:                    ( current / target )
  "http_requests" on pods:  9059m / 10
Min replicas:               2
Max replicas:               10

Events:
  Type    Reason             Age   From                       Message
  ----    ------             ----  ----                       -------
  Normal  SuccessfulRescale  2m    horizontal-pod-autoscaler  New size: 3; reason: pods metric http_requests above target
```

At the current rate of requests per second the deployment will never get to the max value of 10 pods. 
Three replicas are enough to keep the RPS under 10 per each pod.

After the load tests finishes the PHA will down scale the deployment to it's initial replicas:

```
Events:
  Type    Reason             Age   From                       Message
  ----    ------             ----  ----                       -------
  Normal  SuccessfulRescale  5m    horizontal-pod-autoscaler  New size: 3; reason: pods metric http_requests above target
  Normal  SuccessfulRescale  21s   horizontal-pod-autoscaler  New size: 2; reason: All metrics below target
```
