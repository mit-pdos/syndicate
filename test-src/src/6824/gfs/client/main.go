package main

import (
	"fmt"
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
	*client.Client
}

func New() Client {
	c, err := client.NewInCluster()
	if err != nil {
		panic(fmt.Sprintf("failed to contact master: %v\n", err))
	}
	return Client{c}
}

func (c *Client) Pods(component string) []string {
	workers, err := c.Client.Pods(api.NamespaceDefault).List(
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
	return c.Client.Pods(api.NamespaceDefault).Delete(podName, &api.DeleteOptions{})
}

func (c *Client) PodIP(podName string) string {
	p, err := c.Client.Pods(api.NamespaceDefault).Get(podName)
	if err != nil {
		panic(fmt.Sprintf("failed to get pod: %v\n", err))
	}

	return p.Status.PodIP
}

func main() {
	user := os.Args[1]
	workers, _ := strconv.Atoi(os.Args[2])

	fmt.Printf("hello, I'm a client, master @ %s:%s, %d workers\n",
		os.Getenv(fmt.Sprintf("%s_MASTER_SERVICE_HOST", strings.ToUpper(user))),
		os.Getenv(fmt.Sprintf("%s_MASTER_SERVICE_PORT", strings.ToUpper(user))),
		workers,
	)

	c := New()

	wids := c.Pods(fmt.Sprintf("%s-worker", user))

	fmt.Printf("about to kill %s\n", c.PodIP(wids[0]))
	c.Kill(wids[0])
}
