package main

import (
	"fmt"
	"os"
)

func main() {
	fmt.Printf("hello, I'm a client, master @ %s:%s\n",
		os.Getenv("JON_MASTER_SERVICE_HOST"),
		os.Getenv("JON_MASTER_SERVICE_PORT"),
	)
}
