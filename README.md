# Deploy all the things

```bash
make kind
make patch-coredns
make kapp-controller contour

make ssl

make harbor.h1 harbor.h2
```
