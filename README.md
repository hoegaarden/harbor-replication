# Experiment: Bidirectional Replication between 2 Harbor instances

## Quick start

```bash
cat <<EOF | sudo tee /etc/hosts
127.0.0.1 core.harbor.domain
127.0.0.1 core.h1.harbor.domain
127.0.0.1 core.h2.harbor.domain
"$(cat /etc/hosts)"
EOF

git submodule update --init --recursive

make kind
make patch-coredns
make contour

# optionally, preload images
make preload-images

make ssl

make harbor.h1
make harbor.h2

# set up event based replication between the two registries
make harbor.h1.replication
make harbor.h2.replication

make harbor.proxy
```

## Details

This deploys two instances of indipendent harbor container registries `h1` & `h2`. In this setup they are running on the same cluster, in different namespace, but could well be spread acorss different clusters / systems / DCs / ...

Both registries are setup with their individual FQDNs (`core.h1.harbor.domain` & `core.h2.harbor.doman`). In each registry we then deploy a remote registry, pointing to the other registry, and on top of that a replication policy which pushes every update to any artifact in any project across (event triggered push replication).

In addition to that we also deploy a proxy in front of the registries, with its own FQDN (`core.harbor.domain`). This proxy does not do loadbalancing; it points to one specific registry. However, you can have it point to the other registry:
```bash
ACTIVE=core.h2.harbor.domain make harbor.proxy # switch to h2
ACTIVE=core.h1.harbor.domain make harbor.proxy # switch back to h1
```

To make DNS work both inside the cluster and outside, on your host, without the need to have a separate DNS server running, we deploy two workarounds:
- on the host:  
  We add some entries in `/etc/hosts`, which point to `localhost`. Beacuse we deploy the kind cluster with some portforwardings, `tcp/443` and `tcp/80` will be forwarded into the container running the cluster and further to the `nodePort` where contour's envoy is listening.
- in the cluster:  
  In the cluster we patch the coredns configuration and add similar host entries. These are pointing to the `clusterIP` of contour's envoy, which we deploy with a fixed `clusterIP`.

Once everything is up, you can do the following:
- Log into harbor's WebUI at `https://core.harbor.domain`
	- the `admin` user is deployed with the default password `Harbor12345`
- Create a project
- `docker login` to `core.harbor.com`
	- you might need configure your docker client to trust the self-signed cert we've deployed harbor with (can be found at `cert/harbor.pem`)
- Push some images
	- You can use the script `./create-and-push-images.sh ${project} ${nr}`
- Check the replication status at
	- https://core.h1.harbor.domain/harbor/replications
	- https://core.h2.harbor.domain/harbor/replications

### Notes

#### Replication will not replicate you project membership

If you create a new project on `core.harbor.domain`, this will only created on the currently active registry behind the proxy, it will not be replicated. Once you actually push an image to that project, the replication will create the project on the "passive" registry and push the image over there.

However, nothing else will be replicated, i.e no membership configuration will be replicated.

Thus it's a good idea to
- Use an external system to manage your users (LDAP, OIDC, ...)
- Create the projects, their membership configuration, and other settings via automation on all harbor registries

### Known Issues

#### Replication fails on deleting artifacts

When an artifact is deleted, replication pick the deletion up but eventually fails with something like:
```
2021-12-23T11:09:09Z [INFO] [/controller/replication/transfer/image/transfer.go:125]: client for source registry [type: harbor, URL: http://reg-harbor-core:80, insecure: true] created
2021-12-23T11:09:09Z [INFO] [/controller/replication/transfer/image/transfer.go:135]: client for destination registry [type: harbor, URL: https://core.h2.harbor.domain, insecure: true] created
2021-12-23T11:09:21Z [ERROR] [/controller/replication/transfer/image/transfer.go:408]: failed to delete the manifest of artifact foo/nginxinc/nginx-unprivileged:latest on the destination registry: http status code: 401, body: {"errors":[{"code":"UNAUTHORIZED","message":"unauthorized to access repository: foo/nginxinc/nginx-unprivileged, action: delete: unauthorized to access repository: foo/nginxinc/nginx-unprivileged, action: delete"}]}
```

Any other replication (e.g. for new artifacts) seems to still work. There is only one remote registry and one replication policy set up, which all use the same credentials (the global robot user). So it's not celar why deletion fails.

#### Not everything has been tested

Pushing and pulling images through the proxy has been tested as well as using the WebUI.

Other things, like using harbor to host helm charts or Notary has not been tested yet; those might need special attention when it comes to the configuration of the proxy.
