package main

import (
	"fmt"
	"log"
	"net/rpc"
	"os"
	"strconv"
	"strings"

	"k8s.io/kubernetes/pkg/api"
	client "k8s.io/kubernetes/pkg/client/unversioned"
	"k8s.io/kubernetes/pkg/fields"
	"k8s.io/kubernetes/pkg/labels"
)

type Pod string

type Client struct {
	master     *rpc.Client
	kubernetes *client.Client
}

func New(masterAddress string) Client {
	c, err := client.NewInCluster()
	if err != nil {
		panic(fmt.Sprintf("failed to contact master: %v\n", err))
	}

	master, err := rpc.DialHTTP("tcp", masterAddress)
	if err != nil {
		log.Fatal("dialing master:", err)
	}

	return Client{master, c}
}

func (c *Client) Pods(component string) []string {
	workers, err := c.kubernetes.Pods(api.NamespaceDefault).List(
		labels.SelectorFromSet(labels.Set{
			"component": component,
		}),
		fields.Everything(),
	)
	if err != nil {
		panic(fmt.Sprintf("failed to get workers: %v\n", err))
	}

	wids := make([]string, 0, len(workers.Items))
	for _, pod := range workers.Items {
		wids = append(wids, pod.ObjectMeta.Name)
	}

	return wids
}

func (c *Client) Kill(podName string) error {
	return c.kubernetes.Pods(api.NamespaceDefault).Delete(podName, &api.DeleteOptions{})
}

func (c *Client) PodIP(podName string) string {
	p, err := c.kubernetes.Pods(api.NamespaceDefault).Get(podName)
	if err != nil {
		panic(fmt.Sprintf("failed to get pod: %v\n", err))
	}

	return p.Status.PodIP
}

func (c *Client) MRPC(method string, args interface{}, reply interface{}) error {
	return c.master.Call("Master."+method, args, reply)
}

func main() {
	user := os.Args[1]
	workers, _ := strconv.Atoi(os.Args[2])

	masterAddress := fmt.Sprintf(
		"%s:%s",
		os.Getenv(fmt.Sprintf("%s_MASTER_SERVICE_HOST", strings.ToUpper(user))),
		os.Getenv(fmt.Sprintf("%s_MASTER_SERVICE_PORT", strings.ToUpper(user))),
	)

	fmt.Printf("hello, I'm a client, master @ %s, %d workers\n",
		masterAddress,
		workers,
	)

	c := New(masterAddress)

	var chunkservers []string
	err := c.MRPC("Servers", &struct{}{}, &chunkservers)
	if err != nil {
		log.Fatal("get chunkservers:", err)
	}

	wids := c.Pods(fmt.Sprintf("%s-worker", user))
	var wips []string
	for _, wid := range wids {
		wips = append(wips, c.PodIP(wid))
	}

	fmt.Println("chunkservers:", chunkservers, "\nwidp:", wips)
	fmt.Printf("about to kill %s\n", c.PodIP(wids[0]))
	c.Kill(wids[0])
}
