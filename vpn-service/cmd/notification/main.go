package main

import (
	"fmt"
	"log"
	"os"
)

func main() {
	port := os.Getenv("NOTIFICATION_PORT")
	if port == "" {
		port = "3000"
	}

	log.Printf("Starting Notification service on port %s", port)

	// TODO: Initialize notification service
	// - Connect to RabbitMQ
	// - Connect to Telegram Bot API
	// - Subscribe to events from other services
	// - Start HTTP server for health checks

	fmt.Printf("Notification service listening on :%s\n", port)
	select {}
}
