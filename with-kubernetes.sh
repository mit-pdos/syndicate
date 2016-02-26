#!/bin/bash

user=$(echo "$1" | tr -cd 'a-z0-9')

if [ "$user" == "client" ]; then
	echo "ERROR: user cannot be 'client'"
	exit 1
fi

tarball=$2
workers=$(echo "$3" | tr -cd '0-9')
clients=$workers

if [ -z "$user" ] || [ -z "$tarball" ] || [ -z "$workers" ]; then
	echo "Usage: $0 USER TARBALL WORKERS"
	exit 1
fi


if [ ! -e "$tarball" ]; then
	echo "ERROR: file '$tarball' does not exist"
	exit 1
fi

kubectl="kubectl"
kubectl=~/"dev/others/kubernetes/cluster/kubectl.sh"

port=$("$kubectl" get svc/docker-registry -o=go-template --template="{{index .spec.ports 0 \"nodePort\"}}")
registry="docker-registry:$port"
client_image="$registry/client-image"

## 0. check that cluster has enough capacity to schedule job {{{

# }}}

## 1. create a docker image from the tarball {{{
realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}
workdir=$(mktemp -d "docker-build-${user}.XXXXXXXXXX")
cp -H "$(realpath "$tarball")" "$workdir/source.tgz"
pushd "$workdir" || exit 1

image="$user-image"
cat > Dockerfile <<EOF
FROM golang:1.6
MAINTAINER Jon Gjengset <jon@thesquareplanet.com>

ADD source.tgz /go
ENV GOPATH /go
RUN go install $user/gfs/...
EOF
docker build -t "$image" .

popd
rm -rf "$workdir"
# }}}

## 2. upload docker image to private registry {{{
upload() {
	image=$1
	docker tag "$image" "$registry/$image" > /dev/stderr
	docker push "$registry/$image" > /dev/stderr
	echo "$registry/$image"
}
image=$(upload "$image")
# }}}

recipes=$(mktemp -d "kube-recipes-${user}.XXXXXXXXXX")

## 3. create a master service with a single master {{{
cat > "$recipes/master_svc.yaml" <<EOF
kind: Pod
apiVersion: v1
metadata:
  name: $user-master
  labels:
    component: $user-master
spec:
  containers:
    - name: $user-master
      image: $image
      command: ["/go/bin/master"]
      ports:
        - containerPort: 8080
  restartPolicy: Never
---
kind: Service
apiVersion: v1
metadata:
  name: $user-master
spec:
  ports:
    - port: 8080
      targetPort: 8080
  selector:
    component: $user-master
EOF
"$kubectl" create -f "$recipes/master_svc.yaml"
# }}}

## 4. wait for master to be up-and-running {{{
while /bin/true; do
	sleep .5
	state=$("$kubectl" get "po/$user-master" -o=go-template --template='{{index . "status" "phase"}}')
	if [[ "$state" == "Running" ]]; then
		break
	fi
	if [[ "$state" != "Pending" ]]; then
		echo "svc in unexpected state '$state'"
		exit 1
	fi
done
# }}}

## 5. create a worker pool
cat > "$recipes/worker_rc.yaml" <<EOF
kind: ReplicationController
apiVersion: v1
metadata:
  name: $user-workers
spec:
  replicas: $workers
  selector:
    component: $user-worker
  template:
    metadata:
      labels:
        component: $user-worker
    spec:
      containers:
        - name: $user-worker
          image: $image
          command: ["/go/bin/worker"]
          ports:
            - containerPort: 8080
EOF
"$kubectl" create -f "$recipes/worker_rc.yaml"
# }}}

## 6. create job that spawns clients and depends on the master service {{{
# TODO clients should be passed a secret that allows interacting with k8s API
cat > "$recipes/client_job.yaml" <<EOF
apiVersion: extensions/v1beta1
kind: Job
metadata:
  name: $user-clients
spec:
  completions: $clients
  parallelism: $clients
  template:
    metadata:
      name: $user-client
      labels:
        app: $user-client
    spec:
      containers:
      - name: $user-client
        image: $client_image
        command: ["/go/bin/client", "$user", "$workers"]
      restartPolicy: Never
EOF
"$kubectl" create -f "$recipes/client_job.yaml"
# }}}

## 7. wait for job to complete {{{
while /bin/true; do
	sleep 1
	ok=$("$kubectl" get "jobs/$user-clients" -o=go-template --template='{{index . "status" "succeeded"}}')
	if [[ "$ok" == "$clients" ]]; then
		break
	fi
	if [[ "$ok" != "<no value>" ]]; then
		echo "job has unexpected ok '$ok'"
		exit 1
	fi
done
# }}}

## 8. Collect pod output for all clients {{{
for pod in $("$kubectl" get pods --selector=app="$user-client" --output=jsonpath={.items..metadata.name}); do
	"$kubectl" logs "$pod"
done
# }}}

## 8. kill master and all workers {{{
"$kubectl" delete -f "$recipes"
rm -rf "$recipes"
# }}}
