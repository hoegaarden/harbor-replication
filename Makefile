SHELL := /usr/bin/env bash -eu -o pipefail

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

harbor.deploy: ssl
	ytt -f ns.yml -v ns=$(NS) \
		| kubectl apply -f -
	kubectl --namespace $(NS) create secret tls harbor-tls --cert cert/harbor.pem --key cert/harbor.key --dry-run=client -o yaml \
		| kubectl apply -f -
	helm template reg ./harbor \
		-f <( ytt -f harbor.values.yml -v hostname.core=$(CORE) -v hostname.notary=$(NOTARY) ) \
			| kubectl --namespace $(NS) apply -f -

	mkdir -p tmp
	API_CA_FILE=cert/harbor.pem API_BASE='https://$(CORE)' API_USER='admin' API_PASS='Harbor12345' USER='replication' ./scripts/ensureRobot.sh \
		> "tmp/$(NS)-robo-creds"

harbor.h1: NS=h1
harbor.h1: CORE=core.$(NS).harbor.domain
harbor.h1: NOTARY=notary.$(NS).harbor.domain
harbor.h1: harbor.deploy

harbor.h2: NS=h2
harbor.h2: CORE=core.$(NS).harbor.domain
harbor.h2: NOTARY=notary.$(NS).harbor.domain
harbor.h2: harbor.deploy

harbor.replication.deploy:
	API_CA_FILE=cert/harbor.pem API_BASE='https://$(CORE)' API_USER='admin' API_PASS='Harbor12345' \
	REG_NAME='$(REG_NAME)' REP_NAME='$(REP_NAME)' REMOTE_INFO='$(REMOTE_INFO)' \
		./scripts/ensureReplication.sh

harbor.h1.replication: CORE=core.h1.harbor.domain
harbor.h1.replication: REMOTE_INFO=tmp/h2-robo-creds
harbor.h1.replication: REG_NAME=h2
harbor.h1.replication: REP_NAME=h1-to-h2
harbor.h1.replication: harbor.replication.deploy

harbor.h2.replication: CORE=core.h2.harbor.domain
harbor.h2.replication: REMOTE_INFO=tmp/h1-robo-creds
harbor.h2.replication: REG_NAME=h1
harbor.h2.replication: REP_NAME=h2-to-h1
harbor.h2.replication: harbor.replication.deploy
