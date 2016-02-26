#!/bin/bash

client_tarball="$1"
if [ ! -e "$client_tarball" ]; then
	echo "ERROR: file '$client_tarball' does not exist"
	exit 1
fi

kubectl="kubectl"
kubectl=~/"dev/others/kubernetes/cluster/kubectl.sh"

# for cluster:
#  - ensure that maxkubelets=1
#  - ensure each node has access to docker private registry:
#    docker login [private server]
#    for n in $(kubectl get nodes -o template --template=' '); do
#      scp ~/.dockercfg root@$n:/root/.dockercfg;
#    done
#  - ensure docker registry has client image

## 1. provision EC2 machines {{{
#export KUBERNETES_PROVIDER=aws
#export KUBE_AWS_ZONE=us-east-1
#export NUM_MINIONS=2
#export MINION_SIZE=t2.micro
#export INSTANCE_PREFIX=6824-cluster
#curl -sS https://get.k8s.io | bash
# }}}

## 2. launch a private docker registry for student images {{{
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
     image: distribution/registry:2
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
while /bin/true; do
	state=$("$kubectl" get po/docker-registry -o=go-template --template='{{index . "status" "phase"}}')
	if [[ "$state" == "Running" ]]; then
		break
	fi
	if [[ "$state" != "Pending" ]]; then
		echo "po in unexpected state '$state'"
		exit 1
	fi
done

ip=$("$kubectl" get po/docker-registry -o=go-template --template='{{index . "status" "hostIP"}}')
port=$("$kubectl" get svc/docker-registry -o=go-template --template="{{index .spec.ports 0 \"nodePort\"}}")
if ! grep docker-registry /etc/hosts; then
	echo "$ip docker-registry" | sudo tee -a /etc/hosts
fi
sudo sed -i "/docker-registry/ s/^[^ ]*/$ip/" /etc/hosts
registry="docker-registry:$port"

# import certificate
certd="/etc/docker/certs.d/docker-registry:$port"
sudo mkdir -p "$certd"
"$kubectl" exec docker-registry -- cat /certs/domain.crt | sudo tee "$certd/ca.crt"
# }}}

## 3. build and upload client image {{{

# First, send golang 1.6 to private registry
# This doesn't help because of https://github.com/docker/distribution/issues/1495
#docker pull "golang:1.6"
#docker tag "golang:1.6" "$registry/golang:1.6"
#docker push "$registry/golang:1.6"

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}
workdir=$(mktemp -d "docker-build-client.XXXXXXXXXX")
cp -H "$(realpath "$client_tarball")" "$workdir/source.tgz"
pushd "$workdir" || exit 1

cat > Dockerfile <<EOF
#FROM $registry/golang:1.6
FROM golang:1.6
MAINTAINER Jon Gjengset <jon@thesquareplanet.com>

ADD source.tgz /go
RUN cd /go/src && env GOPATH=/go go install 6824/gfs/... && cd / && rm -rf /go/src && rm -rf /go/pkg
EOF

#rapi_port=$("$kubectl" get svc/docker-registry -o=go-template --template="{{index .spec.ports 1 \"nodePort\"}}")
#rapi="docker-registry:$rapi_port"
#image="client-image"
#tar cz -C "$workdir" . | curl \
#    --data-binary @- \
#    --header 'Content-Type: application/x-tar' \
#    --no-buffer \
#    --capath "$certd" \
#    --cacert "$certd/ca.crt" \
#    "https://$rapi/build?t=$image"

image="client-image"
docker build -t "$image" .

popd
rm -rf "$workdir"

docker tag "$image" "$registry/$image"
docker push "$registry/$image"
# }}}

## 4. get user to modify all servers to support registry
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
echo ""
echo -n "Then press <Enter> to continue..."
read -r
