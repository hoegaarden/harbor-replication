CONTOUR_MANIFEST ?= https://projectcontour.io/quickstart/contour.yaml
CONTOUR_NODE_PORT_HTTP ?= 30950  # needs to match port forwarding in kind.yaml
CONTOUR_NODE_PORT_HTTPS ?= 30951 # needs to match port forwarding in kind.yaml
CONTOUR_CLUSTER_IP ?= 10.96.255.254

KAPP_MANIFEST ?= https://github.com/vmware-tanzu/carvel-kapp-controller/releases/latest/download/release.yml

CERT_CONFIG ?= harbor.ssl.cfg

kind:
	kind create cluster --name harbor --config kind.yml
kind.delete:
	kind delete cluster --name harbor

patch-coredns:
	CONTOUR_CLUSTER_IP=$(CONTOUR_CLUSTER_IP) envsubst <coredns.cm.yml \
		| kubectl apply -f -
	kubectl --namespace kube-system rollout restart deploy coredns

kapp-controller:
	kubectl apply -f $(KAPP_MANIFEST)
	kubectl --namespace kapp-controller wait --for condition=Ready=true pod --selector app=kapp-controller
kapp-controller.delete:
	kubectl delete -f $(KAPP_MANIFEST)

contour:
	curl -fsL $(CONTOUR_MANIFEST) \
		| ytt -f - -f contour.patch.yml \
			--data-value-yaml nodePort.http=$(CONTOUR_NODE_PORT_HTTP) \
			--data-value-yaml nodePort.https=$(CONTOUR_NODE_PORT_HTTPS) \
			--data-value-yaml clusterIP=$(CONTOUR_CLUSTER_IP) \
		| kubectl apply -f -
	kubectl --namespace projectcontour wait --for condition=Ready=true pod --selector app=envoy
	kubectl --namespace projectcontour wait --for condition=Ready=true pod --selector app=contour
contour.delete:
	kubectl delete --timeout 3m namespace projectcontour

cert/harbor.key:
	mkdir -p cert
	certtool --generate-privkey \
		--outfile cert/harbor.key
cert/harbor.pem: cert/harbor.key $(CERT_CONFIG)
	certtool --generate-self-signed \
		--template $(CERT_CONFIG) \
		--load-privkey cert/harbor.key \
		--outfile cert/harbor.pem
ssl: cert/harbor.pem
ssl.delete:
	rm -rf cert/
