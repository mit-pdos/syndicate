# Sourced from here https://gist.github.com/matthiasr/8333ae8536036614265a
# Which came from https://groups.google.com/forum/#!topic/google-containers/8CcyB6JEeaQ

KUBERNETES_VERSION ?= 1.1.8
KUBERNETES_SOURCE_URL = https://github.com/kubernetes/kubernetes/archive/v$(KUBERNETES_VERSION).tar.gz
ROOT_DIR:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

client.tgz: src/6824/gfs/client/main.go src/vendor/k8s.io/kubernetes/.available src/vendor/k8s.io/kubernetes/.lifted_godeps
	rm -f $@
	cd src && env GOPATH=$(ROOT_DIR) go get 6824/gfs/...
	tar czf $@ \
		--exclude ./src/student \
		--exclude ./Makefile \
		--exclude ./bin \
		--exclude ./pkg \
		--exclude ./build \
		--exclude './*.tgz' \
		--exclude './*.tar.gz' \
		.

student.tgz: src/student/gfs/master/main.go src/student/gfs/worker/main.go
	rm -f $@
	cd src && env GOPATH=$(ROOT_DIR) go get student/gfs/...
	tar czf $@ \
		--exclude ./src/6824/gfs/client \
		--exclude ./src/vendor \
		--exclude ./Makefile \
		--exclude ./bin \
		--exclude ./pkg \
		--exclude ./build \
		--exclude './*.tgz' \
		--exclude './*.tar.gz' \
		.


# Lift a source tree into the vendor tree, skipping Godeps
src/vendor/%/.available: build/$(KUBERNETES_VERSION)/%/.available
	mkdir -p $(@D)
	rsync -a --exclude=Godeps $(<D)/ $(@D)

# For a given source tree, lift all its godeps into the vendor tree
src/vendor/%/.lifted_godeps: build/$(KUBERNETES_VERSION)/%/.available
	mkdir -p src/vendor/
	find $(<D) -type d -name Godeps -exec rsync -a '{}/_workspace/src/' src/vendor/ ';'
	touch $@

build/$(KUBERNETES_VERSION)/k8s.io/kubernetes/.available:
	mkdir -p $(@D)
	curl -sSLf $(KUBERNETES_SOURCE_URL) |\
		tar --wildcards -C $(@D) --strip-components=1 -zx
	touch $@

.PHONY: clean
clean::
	rm -rf build src/vendor
