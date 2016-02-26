package main

import (
	"6824/gfs"
	"fmt"
	"log"
	"net"
	"net/rpc"
	"os"
	"os/signal"
	"strings"
)

func main() {
	masterAddress := fmt.Sprintf(
		"%s:%s",
		os.Getenv("STUDENT_MASTER_SERVICE_HOST"),
		os.Getenv("STUDENT_MASTER_SERVICE_PORT"),
	)

	addrs, err := net.InterfaceAddrs()
	if err != nil {
		log.Fatal("could not get local IPs:", err)
	}

	var workerAddress string
	for i, addr := range addrs {
		if addr.Network() != "ip+net" {
			fmt.Printf("skipping worker addr[%d] = %v (%s != ip+net)\n", i, addr, addr.Network())
			continue
		}

		host := strings.SplitN(addr.String(), "/", 2)[0]
		if host == "::1" || host == "127.0.0.1" {
			fmt.Printf("skipping worker addr[%d] = %v (local address)\n", i, addr)
			continue
		}

		workerAddress = host
		fmt.Printf("worker addr[%d] = %v\n", i, host)
		break
	}

	fmt.Printf("hello, I'm worker %s, master @ %s\n",
		workerAddress,
		masterAddress,
	)

	master, err := rpc.DialHTTP("tcp", masterAddress)
	if err != nil {
		log.Fatal("dialing master:", err)
	}

	err = master.Call("Master.Register", gfs.RegisterArgs{
		Me: workerAddress,
	}, &struct{}{})

	if err != nil {
		log.Fatal("registering with master:", err)
	}

	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt, os.Kill)
	<-c
	os.Exit(0)
}
