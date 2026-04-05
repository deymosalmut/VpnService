package main

import (
	"fmt"
	"log"
	"os"
)

func main() {
	port := os.Getenv("USER_MGMT_PORT")
	if port == "" {
		port = "3000"
	}

	log.Printf("Starting User Management service on port %s", port)

	// TODO: Initialize user management service
	// - Connect to PostgreSQL
	// - Connect to RabbitMQ
	// - Subscribe to billing and auth events
	// - Start HTTP server

	fmt.Printf("User Management service listening on :%s\n", port)
	select {}
}
