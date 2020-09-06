# docker-compose DNS in k3s Kubernetes pods

This is a [minimal, reproducible example](https://stackoverflow.com/help/minimal-reproducible-example) how you can access the internal Docker DNS (`127.0.0.11`) from k8s pods in a k3s container.


## Problem Statement

[k3s](https://k3s.io/) allows you to start a [Kubernetes](https://kubernetes.io/) cluster inside a Docker container. Just run a container with the [`rancher/k3s`](https://hub.docker.com/r/rancher/k3s) image.

[`docker-compose`](https://docs.docker.com/compose/) sets up a [network](https://docs.docker.com/compose/networking/) for the containers. Each container can access the other containers in this network by their service name. The internal Docker DNS resolves these names. This DNS is reachable inside the containers on `127.0.0.11`. This IP is set in the file `/etc/resolv.conf` of each container as nameserver.

In the k3s cluster, the [CoreDNS](https://coredns.io/) instance uses the `/etc/resolv.conf` of the node (here: the Docker container `k3s`). However, `127.0.0.11` as internal Docker DNS is not reachable from the pods of the Kubernetes cluster. Thus, the other containers in the `docker-compose.yaml` cannot be reached by their names from a pod.


## Example

This example defines three services in the [`docker-compose.yaml`](docker-compose.yaml):
1. A `server` that serves `Hello World!` at `http://server:8080/hello-world`.
2. A `client` that accesses this HTTP service (just to demo how it works in a “normal” docker-compose setting).
3. A `k3s` container that starts a pod that tries to access the HTTP service.

Without the custom [`entrypoint.sh`](entrypoint.sh), accessing the HTTP service from the pod in the k3s container does not work. You get the error:
```
curl: (6) Could not resolve host: server
```


## Solution

The new entrypoint `entrypoint.sh` of the `k3s` container adds `iptables` rules that forwards DNS traffic to the internal Docker DNS. Since the port changes on every start, the following lines determines the correct address the DNS traffic has to be redirected to:

```sh
TCP_DNS_ADDR=$(iptables-save | grep DOCKER_OUTPUT | grep tcp | grep -o '127\.0\.0\.11:.*$')
UDP_DNS_ADDR=$(iptables-save | grep DOCKER_OUTPUT | grep udp | grep -o '127\.0\.0\.11:.*$')
```

Next, the rules to forward the traffic look like this:
```sh
iptables -t nat -A PREROUTING -p tcp --dport 53 -j DNAT --to "$TCP_DNS_ADDR"
iptables -t nat -A PREROUTING -p udp --dport 53 -j DNAT --to "$UDP_DNS_ADDR"
```

We tell the CoreDNS service to use the k3s container as DNS server by adding the IP of the container to the `/etc/resolv.conf` file:
```sh
TMP_FILE=$(mktemp)
sed "/nameserver.*/ a nameserver $(hostname -i | cut -f1 -d' ')" /etc/resolv.conf > "$TMP_FILE"
cp "$TMP_FILE" /etc/resolv.conf
rm "$TMP_FILE"
```

That's it. Now, the pods are able to resolve the service names of the other containers defined in the `docker-compose.yaml` file.

```
$ docker-compose exec k3s kubectl logs -f alpine
```
prints `Hello World!` every 10 seconds.
