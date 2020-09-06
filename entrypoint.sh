#!/bin/sh


# Add IP tables rules to access Docker's internal DNS 127.0.0.11 from outside
# based on https://serverfault.com/a/826424

TCP_DNS_ADDR=$(iptables-save | grep DOCKER_OUTPUT | grep tcp | grep -o '127\.0\.0\.11:.*$')
UDP_DNS_ADDR=$(iptables-save | grep DOCKER_OUTPUT | grep udp | grep -o '127\.0\.0\.11:.*$')

iptables -t nat -A PREROUTING -p tcp --dport 53 -j DNAT --to "$TCP_DNS_ADDR"
iptables -t nat -A PREROUTING -p udp --dport 53 -j DNAT --to "$UDP_DNS_ADDR"


# Add this IP to resolv.conf since CoreDNS of k3s uses this file

TMP_FILE=$(mktemp)
sed "/nameserver.*/ a nameserver $(hostname -i | cut -f1 -d' ')" /etc/resolv.conf > "$TMP_FILE"
cp "$TMP_FILE" /etc/resolv.conf
rm "$TMP_FILE"


/bin/k3s server
