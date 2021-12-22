kind:
	kind create cluster --name harbor --config kind.yml
kind.delete:
	kind delete cluster --name harbor

KAPP_MANIFEST ?= https://github.com/vmware-tanzu/carvel-kapp-controller/releases/latest/download/release.yml
kapp-controller:
	kubectl apply -f $(KAPP_MANIFEST)
	kubectl --namespace kapp-controller wait --for condition=Ready=true pod --selector app=kapp-controller
kapp-controller.delete:
	kubectl delete -f $(KAPP_MANIFEST)

CONTOUR_MANIFEST ?= https://projectcontour.io/quickstart/contour.yaml
contour:
	curl -fsL $(CONTOUR_MANIFEST) \
		| ytt -f - -f contour.patch.yml \
		| kubectl apply -f -
	kubectl --namespace projectcontour wait --for condition=Ready=true pod --selector app=envoy
	kubectl --namespace projectcontour wait --for condition=Ready=true pod --selector app=contour
contour.delete:
	kubectl delete --timeout 3m namespace projectcontour
