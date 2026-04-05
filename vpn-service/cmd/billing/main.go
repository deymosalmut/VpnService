package main

import (
	"fmt"
	"log"
	"os"
)

func main() {
	port := os.Getenv("BILLING_PORT")
	if port == "" {
		port = "3000"
	}

	log.Printf("Starting Billing service on port %s", port)

	// TODO: Initialize billing service
	// - Connect to PostgreSQL
	// - Connect to RabbitMQ
	// - Initialize payment processors (Cryptomus, SBP)
	// - Start HTTP server

	fmt.Printf("Billing service listening on :%s\n", port)
	select {}
}
