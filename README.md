# Deploy all the things

```bash
make kind
make patch-coredns
make kapp-controller contour

make ssl
```
