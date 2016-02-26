package main

import (
	"fmt"
	"os"
	"os/signal"
)

func main() {
	fmt.Printf("hello, I'm a worker, master @ %s:%s\n",
		os.Getenv("STUDENT_MASTER_SERVICE_HOST"),
		os.Getenv("STUDENT_MASTER_SERVICE_PORT"),
	)

	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt, os.Kill)
	<-c
	os.Exit(0)
}
