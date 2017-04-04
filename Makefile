# Set the build version
ifeq ($(origin VERSION), undefined)
	VERSION := $(shell git describe --tags --always --dirty)
endif
# build date
ifeq ($(origin BUILD_DATE), undefined)
	BUILD_DATE := $(shell date -u)
endif

# Setup some useful vars
PKG = github.com/apprenda/kismatic
HOST_GOOS = $(shell go env GOOS)
HOST_GOARCH = $(shell go env GOARCH)

# Versions of external dependencies
GLIDE_VERSION = v0.11.1
ANSIBLE_VERSION = 2.1.4.0
PROVISIONER_VERSION = v1.1.1
KUBERANG_VERSION = v1.1.2
GO_VERSION = 1.8.0

ifeq ($(origin GLIDE_GOOS), undefined)
	GLIDE_GOOS := $(HOST_GOOS)
endif
ifeq ($(origin GOOS), undefined)
	GOOS := $(HOST_GOOS)
endif

build: bin/$(GOOS)/kismatic

build-inspector:
	@$(MAKE) GOOS=linux bin/inspector/linux/amd64/kismatic-inspector
	@$(MAKE) GOOS=darwin bin/inspector/darwin/amd64/kismatic-inspector

.PHONY: bin/$(GOOS)/kismatic
bin/$(GOOS)/kismatic: vendor
	@echo "building $@"
	@docker run                                                                     \
	    --rm                                                                        \
	    -e GOOS=$(GOOS)                                                             \
	    -u $$(id -u):$$(id -g)                                                      \
	    -v "$(shell pwd)":/go/src/$(PKG)                                            \
	    -w /go/src/$(PKG)                                                           \
	    golang:$(GO_VERSION)                                                        \
	    go build -o $@                                                              \
	        -ldflags "-X main.version=$(VERSION) -X 'main.buildDate=$(BUILD_DATE)'" \
	        ./cmd/kismatic

.PHONY: bin/inspector/$(GOOS)/amd64/kismatic-inspector
bin/inspector/$(GOOS)/amd64/kismatic-inspector: vendor
	@echo "building $@"
	@docker run                                                                      \
	    --rm                                                                         \
	    -e GOOS=$(GOOS)                                                              \
	    -u $$(id -u):$$(id -g)                                                       \
	    -v "$(shell pwd)":/go/src/$(PKG)                                             \
	    -w /go/src/$(PKG)                                                            \
	    golang:$(GO_VERSION)                                                         \
	    go build -o $@                                                               \
	        -ldflags "-X main.version=$(VERSION) -X 'main.buildDate=$(BUILD_DATE)'"  \
	        ./cmd/kismatic-inspector


clean:
	rm -rf bin
	rm -rf out
	rm -rf vendor
	rm -rf vendor-ansible/out
	rm -rf vendor-provision/out
	rm -rf integration/vendor
	rm -rf vendor-kuberang

test: vendor
	@docker run                                                   \
	    --rm                                                      \
	    -u $$(id -u):$$(id -g)                                    \
	    -v "$(shell pwd)":/go/src/$(PKG)                          \
	    -w /go/src/$(PKG)                                         \
	    golang:$(GO_VERSION)                                      \
	    go test ./cmd/... ./pkg/... $(TEST_OPTS)

integration-test: dist just-integration-test

vendor: tools/glide
	./tools/glide install

tools/glide:
	mkdir -p tools
	curl -L https://github.com/Masterminds/glide/releases/download/$(GLIDE_VERSION)/glide-$(GLIDE_VERSION)-$(GLIDE_GOOS)-$(HOST_GOARCH).tar.gz | tar -xz -C tools
	mv tools/$(GLIDE_GOOS)-$(HOST_GOARCH)/glide tools/glide
	rm -r tools/$(GLIDE_GOOS)-$(HOST_GOARCH)

vendor-ansible/out:
	@echo "Vendoring ansible"
	@docker build -t apprenda/vendor-ansible vendor-ansible
	@docker run \
	    --rm \
	    -v $(shell pwd)/vendor-ansible/out:/ansible \
	    apprenda/vendor-ansible \
	    pip install --install-option="--prefix=/ansible" ansible==$(ANSIBLE_VERSION)

vendor-provision/out:
	mkdir -p vendor-provision/out/
	curl -L https://github.com/apprenda/kismatic-provision/releases/download/$(PROVISIONER_VERSION)/provision-darwin-amd64 -o vendor-provision/out/provision-darwin-amd64
	curl -L https://github.com/apprenda/kismatic-provision/releases/download/$(PROVISIONER_VERSION)/provision-linux-amd64 -o vendor-provision/out/provision-linux-amd64
	chmod +x vendor-provision/out/*

vendor-kuberang/$(KUBERANG_VERSION):
	mkdir -p vendor-kuberang/$(KUBERANG_VERSION)
	curl https://kismatic-installer.s3-accelerate.amazonaws.com/kuberang/$(KUBERANG_VERSION)/kuberang-linux-amd64 -o vendor-kuberang/$(KUBERANG_VERSION)/kuberang-linux-amd64

dist: vendor-ansible/out vendor-provision/out vendor-kuberang/$(KUBERANG_VERSION) build build-inspector
	mkdir -p out
	cp bin/$(GOOS)/kismatic out
	mkdir -p out/ansible
	cp -r vendor-ansible/out/* out/ansible
	rm -rf out/ansible/playbooks
	cp -r ansible out/ansible/playbooks
	mkdir -p out/ansible/playbooks/inspector
	cp -r bin/inspector/* out/ansible/playbooks/inspector
	mkdir -p out/ansible/playbooks/kuberang/linux/amd64/
	cp vendor-kuberang/$(KUBERANG_VERSION)/kuberang-linux-amd64 out/ansible/playbooks/kuberang/linux/amd64/kuberang
	cp vendor-provision/out/provision-$(GOOS)-amd64 out/provision
	rm -f out/kismatic.tar.gz
	tar -czf kismatic.tar.gz -C out .
	mv kismatic.tar.gz out

docker: GOOS=linux
docker: vendor-ansible/out vendor-provision/out vendor-kuberang/$(KUBERANG_VERSION) build-inspector
	@$(MAKE) GOOS=linux bin/linux/kismatic
	mkdir -p out-docker
	cp bin/linux/kismatic out-docker
	mkdir -p out-docker/ansible
	cp -r vendor-ansible/out/* out-docker/ansible
	rm -rf out-docker/ansible/playbooks
	cp -r ansible out-docker/ansible/playbooks
	mkdir -p out-docker/ansible/playbooks/inspector
	cp -r bin/inspector/* out-docker/ansible/playbooks/inspector
	mkdir -p out-docker/ansible/playbooks/kuberang/linux/amd64/
	cp vendor-kuberang/$(KUBERANG_VERSION)/kuberang-linux-amd64 out-docker/ansible/playbooks/kuberang/linux/amd64/kuberang
	cp docker/Dockerfile.kismatic out-docker/Dockerfile.kismatic
	docker build -f out-docker/Dockerfile.kismatic -t apprenda/kismatic:latest --build-arg ANSIBLE_VERSION=$(ANSIBLE_VERSION) out-docker
	docker tag apprenda/kismatic:latest apprenda/kismatic:$(VERSION)
	rm -rf out-docker

integration/vendor: tools/glide
	go get github.com/onsi/ginkgo/ginkgo
	cd integration && ../tools/glide install

just-integration-test: integration/vendor
	ginkgo --skip "\[slow\]" -p -v integration

slow-integration-test: integration/vendor
	ginkgo --focus "\[slow\]" -p -v integration

serial-integration-test: integration/vendor
	ginkgo -v integration

focus-integration-test: integration/vendor
	ginkgo --focus $(FOCUS) -v integration

docs/generate-kismatic-cli:
	mkdir -p docs/kismatic-cli
	go run cmd/kismatic-docs/main.go
	cp docs/kismatic-cli/kismatic.md docs/kismatic-cli/README.md

version: FORCE
	@echo VERSION=$(VERSION)
	@echo GLIDE_VERSION=$(GLIDE_VERSION)
	@echo ANSIBLE_VERSION=$(ANSIBLE_VERSION)
	@echo PROVISIONER_VERSION=$(PROVISIONER_VERSION)

trigger-ci-slow-tests:
	@echo Triggering build on snap with slow tests
	@curl -u $(SNAP_USER):$(SNAP_API_KEY) -X POST -H 'Accept: application/vnd.snap-ci.com.v1+json' -H 'Content-type: application/json' https://api.snap-ci.com/project/apprenda/kismatic/branch/master/trigger --data '{"env":{"RUN_SLOW_TESTS": "true" }}'

trigger-pr-slow-tests:
	@echo Trigger build for PR $(SNAP_PR_NUMBER)
	@curl -u $(SNAP_USER):$(SNAP_API_KEY) -X POST -H 'Accept: application/vnd.snap-ci.com.v1+json' -H 'Content-type: application/json' https://api.snap-ci.com/project/apprenda/kismatic/pull/$(SNAP_PR_NUMBER)/trigger --data '{"env":{"RUN_SLOW_TESTS": "true" }}'

FORCE:
