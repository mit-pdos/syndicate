#!/bin/bash

# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

user=$(echo "$1" | tr -cd 'a-z0-9')

if [ "$user" == "client" ]; then
	err "user cannot be 'client'"
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
	err "file '$tarball' does not exist"
	exit 1
fi

sec "Run workload with $workers workers for user '$user'"

kubectl="kubectl"
kubectl=~/"dev/others/kubernetes/cluster/kubectl.sh"

msg "Using kubectl: $kubectl"

port=$("$kubectl" get svc/docker-registry -o=go-template --template="{{index .spec.ports 0 \"nodePort\"}}")
registry="docker-registry:$port"
client_image="$registry/client-image"

msg "Using registry: $registry"
msg "Using client image: $client_image"

## 0. check that cluster has enough capacity to schedule job {{{
msg "Check cluster capacity"
# }}}

## 1. provision user image {{{
msg "Provision user image"
realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

image="$user-image"
msg2 "Build image '$image'"

workdir=$(mktemp -d "docker-build-${user}.XXXXXXXXXX")
cp -H "$(realpath "$tarball")" "$workdir/source.tgz"
pushd "$workdir" || exit 1

cat > Dockerfile <<EOF
FROM golang:1.6
MAINTAINER Jon Gjengset <jon@thesquareplanet.com>

ADD source.tgz /go
RUN cd /go/src && env GOPATH=/go go install $user/gfs/... && cd / && rm -rf /go/src && rm -rf /go/pkg
EOF
docker build -t "$image" .

popd
rm -rf "$workdir"

# upload docker image to private registry
msg2 "Push user image to registry"
docker tag "$image" "$registry/$image" > /dev/stderr
docker push "$registry/$image" > /dev/stderr
image="$registry/$image"
# }}}

recipes=$(mktemp -d "kube-recipes-${user}.XXXXXXXXXX")

## 2. create a master service with a single master {{{
msg "Start user's master daemon"
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

# wait for master to be up-and-running
msg2 "Wait for master to start"
while /bin/true; do
	sleep .5
	state=$("$kubectl" get "po/$user-master" -o=go-template --template='{{index . "status" "phase"}}')
	if [[ "$state" == "Running" ]]; then
		break
	fi
	if [[ "$state" != "Pending" ]]; then
		err2 "svc in unexpected state '$state'"
		exit 1
	fi
done
msg2 "Master ready"
# }}}

## 3. create a worker pool
msg "Start user worker pool"
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

## 4. create job that spawns clients and depends on the master service {{{
msg "Run client workload"
msg2 "Start clients"
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

cleanup() {
	msg "Clean up after user workload"
	msg2 "Stop servers"
	"$kubectl" delete -f "$recipes"
	msg2 "Delete recipes"
	rm -rf "$recipes"
}

# wait for job to complete
msg2 "Wait for workload to complete"
while /bin/true; do
	sleep 1
	ok=$("$kubectl" get "jobs/$user-clients" -o=go-template --template='{{index . "status" "succeeded"}}' 2>/dev/null)
	if [[ "$ok" == "$clients" ]]; then
		break
	fi
	if [[ "$ok" != "<no value>" ]]; then
		"$kubectl" get "jobs/$user-clients" -o=go-template --template='{{index . "status"}}'
		if [ $? -ne 0 ]; then
			warn2 "job has been terminated"
		else
			err2 "workload terminated in unexpected state"
		fi
		cleanup
		exit 1
	fi
done
msg2 "Workload done"
# }}}

## 5. Collect pod output for all clients {{{
msg "Collect workload client output"
for pod in $("$kubectl" get pods --selector=app="$user-client" --output=jsonpath={.items..metadata.name}); do
	msg2 "Output for client '$pod':"
	"$kubectl" logs "$pod"
done
# }}}

## 6. kill master and all workers {{{
cleanup
# }}}

msg "All done!"
