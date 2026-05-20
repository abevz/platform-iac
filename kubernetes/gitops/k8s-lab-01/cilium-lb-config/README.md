# Cilium LoadBalancer Config

This directory contains a public-safe example for exposing selected
`LoadBalancer` services on a local network with Cilium LB IPAM and L2
announcements.

## What it does

- `CiliumLoadBalancerIPPool` provides an example allocation range from
  `192.0.2.200-192.0.2.219` (`TEST-NET-1`, reserved for documentation).
- `CiliumL2AnnouncementPolicy` announces only services labeled with
  `networking.platform.example.com/l2-announce: "true"`.

## How to adapt for a real cluster

1. Replace the example address range with a free range from your LAN.
2. Label the service you want to expose, for example an ingress gateway.
3. If you use `.spec.loadBalancerClass`, set it to `io.cilium/l2-announcer`.
4. Keep `externalTrafficPolicy: Cluster` for services announced via L2.

Example service metadata:

```yaml
metadata:
  labels:
    networking.platform.example.com/l2-announce: "true"
```
