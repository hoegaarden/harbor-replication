# Deploy all the things

```bash
make kind
make patch-coredns
make kapp-controller contour

make ssl

make harbor.h1 harbor.h2

# set up event based replication between the two registries
make harbor.h1.replication
make harbor.h2.replication

make harbor.proxy
```
