package main

import (
	"fmt"
	"log"
	"net/rpc"
	"os"
	"strconv"
	"strings"
	"time"

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

func (c *Client) State(podName string) (string, error) {
	p, err := c.kubernetes.Pods(api.NamespaceDefault).Get(podName)
	if err != nil {
		return "", err
	}

	return string(p.Status.Phase), nil
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

	var wids []string
	fmt.Println("Waiting for all workers to be scheduled")
	for len(wids) != workers {
		wids = c.Pods(fmt.Sprintf("%s-worker", user))
		<-time.After(50 * time.Millisecond)
	}
	for _, wid := range wids {
		fmt.Println(" -", wid)
	}

	fmt.Println("Waiting for all workers to be running")
	for _, wid := range wids {
		var err error
		var p string
		for {
			p, err = c.State(wid)
			if err != nil {
				log.Fatal("unknown worker", wid, err)
			}
			if p == "Running" {
				break
			}
			if p != "Pending" {
				log.Fatal("worker in unknown state", p)
			}
		}
	}

	var chunkservers []string
	fmt.Println("Waiting for all workers to register with master")
	for len(chunkservers) != workers {
		chunkservers = chunkservers[:0]
		err := c.MRPC("Servers", &struct{}{}, &chunkservers)
		if err != nil {
			log.Fatal("get chunkservers:", err)
		}
		<-time.After(50 * time.Millisecond)
	}
	for _, cs := range chunkservers {
		fmt.Println(" -", cs)
	}

	fmt.Println("Getting pod IPs")
	wips := make([]string, 0, len(wids))
	for _, wid := range wids {
		wips = append(wips, c.PodIP(wid))
	}
	for _, wip := range wips {
		fmt.Println(" -", wip)
	}

	fmt.Println("chunkservers:", chunkservers, "\nwidp:", wips)

	fmt.Printf("about to kill %s\n", c.PodIP(wids[0]))
	c.Kill(wids[0])

	i := 0
	for i < 10 {
		p, err := c.State(wids[0])
		if err != nil {
			fmt.Println("getting pod state returned:", err)
			break
		}
		if p == "Running" {
			continue
		}
		if p == "Terminating" {
			continue
		}
		fmt.Println("pod state is:", p)
		<-time.After(50 * time.Millisecond)
		i++
	}

	i = 0
	var nchunkservers []string
	fmt.Println("checking that master eventually gets another chunkserver")
	for len(nchunkservers) <= len(chunkservers) && i < 10 {
		nchunkservers = nchunkservers[:0]
		err := c.MRPC("Servers", &struct{}{}, &nchunkservers)
		if err != nil {
			log.Fatal("get chunkservers:", err)
		}
		<-time.After(200 * time.Millisecond)
		i++
	}

	if len(nchunkservers) > len(chunkservers) {
		fmt.Println("master got new chunkserver", nchunkservers[len(nchunkservers)-1])
	} else {
		fmt.Println("ERROR: master did not get a new chunkserver. compare", chunkservers, nchunkservers)
	}
}
