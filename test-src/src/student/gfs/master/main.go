package main

import (
	"6824/gfs"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/rpc"
	"os"
	"os/signal"
	"sync"
)

type Master struct {
	mu sync.Mutex
	//chunkservers []*rpc.Client
	chunkservers []string
}

func (m *Master) Register(args *gfs.RegisterArgs, reply *struct{}) error {
	m.mu.Lock()
	m.chunkservers = append(m.chunkservers, args.MyIP)
	fmt.Println("new chunkserver:", args.MyIP)
	m.mu.Unlock()
	return nil
}

func (m *Master) Servers(args *struct{}, reply *[]string) error {
	m.mu.Lock()
	(*reply) = make([]string, len(m.chunkservers))
	copy(*reply, m.chunkservers)
	m.mu.Unlock()
	return nil
}

func main() {
	println("hello, I'm the master")

	master := new(Master)
	rpc.Register(master)
	rpc.HandleHTTP()
	l, e := net.Listen("tcp", ":8080")
	if e != nil {
		log.Fatal("master listen error:", e)
	}
	go http.Serve(l, nil)

	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt, os.Kill)
	<-c

	master.mu.Lock()
	fmt.Println("chunkservers:", master.chunkservers)
	master.mu.Unlock()
	os.Exit(0)
}
