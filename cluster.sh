#!/bin/bash

# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

client_tarball="$1"
if [ ! -e "$client_tarball" ]; then
	err "file '$client_tarball' does not exist"
	exit 1
fi

sec "Provisioning kuberenetes cluster"

kubectl="kubectl"
kubectl=~/"dev/others/kubernetes/cluster/kubectl.sh"

msg "Using kubectl: $kubectl"

# for cluster:
#  - ensure that maxkubelets=1
#  - ensure each node has access to docker private registry:
#    docker login [private server]
#    for n in $(kubectl get nodes -o template --template=' '); do
#      scp ~/.dockercfg root@$n:/root/.dockercfg;
#    done
#  - ensure docker registry has client image

## 1. provision EC2 machines {{{
msg "Spawn EC2 machines"
#export KUBERNETES_PROVIDER=aws
#export KUBE_AWS_ZONE=us-east-1
#export NUM_MINIONS=2
#export MINION_SIZE=t2.micro
#export INSTANCE_PREFIX=6824-cluster
#curl -sS https://get.k8s.io | bash
# }}}

## 2. launch a private docker registry for student images {{{
msg "Start private docker registry"

msg2 "Checking if registry is already running"
newreg=0
"$kubectl" get po/docker-registry
if [ $? -ne 0 ]; then
	msg2 "Not running; starting a new instance"
	newreg=1

	"$kubectl" create -f - <<EOF
kind: Pod
apiVersion: v1
metadata:
  name: docker-registry
  labels:
    component: docker-registry
spec:
  containers:
   - name: docker-registry
     image: library/registry:2
     env:
       - name: REGISTRY_HTTP_TLS_CERTIFICATE
         value: /certs/domain.crt
       - name: REGISTRY_HTTP_TLS_KEY
         value: /certs/domain.key
     command:
       - /bin/bash
       - "-c"
       - >-
         mkdir -p /certs
         &&
         openssl req -new -newkey rsa:1024 -days 365 -nodes -x509
         -subj "/C=US/ST=MA/L=Cambridge/O=MIT/CN=docker-registry"
         -keyout /certs/domain.key
         -out /certs/domain.crt
         &&
         registry /etc/docker/registry/config.yml
     ports:
       - containerPort: 5000
  restartPolicy: Never
---
kind: Service
apiVersion: v1
metadata:
  name: docker-registry
spec:
  ports:
    - port: 5000
      targetPort: 5000
  type: NodePort
  selector:
    component: docker-registry
EOF

	# wait for service to start
	msg2 "Wait for registry to start"
	while /bin/true; do
		state=$("$kubectl" get po/docker-registry -o=go-template --template='{{index . "status" "phase"}}')
		if [[ "$state" == "Running" ]]; then
			break
		fi
		if [[ "$state" != "Pending" ]]; then
			err2 "Registry in unexpected state '$state'"
			exit 1
		fi
	done
fi

ip=$("$kubectl" get po/docker-registry -o=go-template --template='{{index . "status" "hostIP"}}')
port=$("$kubectl" get svc/docker-registry -o=go-template --template="{{index .spec.ports 0 \"nodePort\"}}")
registry="docker-registry:$port"
if [ "$newreg" -eq 1 ]; then
	msg2 "Registry ready at $ip:$port"

	msg2 "Inject registry name 'docker-registry' in /etc/hosts"
	if ! grep docker-registry /etc/hosts; then
		echo "$ip docker-registry" | sudo tee -a /etc/hosts
	fi
	sudo sed -i "/docker-registry/ s/^[^ ]*/$ip/" /etc/hosts

	# import certificate
	msg2 "Import registry TLS certificate"
	certd="/etc/docker/certs.d/docker-registry:$port"
	sudo mkdir -p "$certd"
	"$kubectl" exec docker-registry -- cat /certs/domain.crt | sudo tee "$certd/ca.crt"
else
	warn2 "Registry already running on $ip:$port"
fi
# }}}

## 3. build and upload client image {{{
msg "Provision client image"
realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

msg2 "Build client image"
workdir=$(mktemp -d "docker-build-client.XXXXXXXXXX")
cp -H "$(realpath "$client_tarball")" "$workdir/source.tgz"
pushd "$workdir" || exit 1

cat > Dockerfile <<EOF
FROM golang:1.6
MAINTAINER Jon Gjengset <jon@thesquareplanet.com>

ADD source.tgz /go
RUN cd /go/src && env GOPATH=/go go install 6824/gfs/... && cd / && rm -rf /go/src && rm -rf /go/pkg
EOF

image="client-image"
docker build -t "$image" .

popd
rm -rf "$workdir"

msg2 "Push client image to registry"
docker tag "$image" "$registry/$image"
docker push "$registry/$image"
# }}}

## 4. get user to modify all servers to support registry
if [ "$newreg" -eq 1 ]; then
	msg "Prepare nodes for workload"
	echo ""
	echo "Okay, here's the deal -- we've set up a private Docker registry, but"
	echo "it uses a cluster-internal DNS name that the node doesn't have access"
	echo "to. Hence, we need to inject the cluster DNS server into the node's"
	echo "hosts file. In addition, we need to make the node's Docker server trust"
	echo "our registry's HTTPS key!"
	echo ""
	echo "Please run the following commands to set all this up."
	echo "The lines beginning with 'ssh node' should be run for every node."
	echo ""
	echo " - kubectl exec docker-registry cat /certs/domain.crt > registry.crt"
	echo " * ssh node sudo mkdir -p $certd"
	echo " * ssh node sudo tee $certd/ca.crt < registry.crt"
	echo " * echo '$ip docker-registry' | ssh node sudo tee -a /etc/hosts"
fi
