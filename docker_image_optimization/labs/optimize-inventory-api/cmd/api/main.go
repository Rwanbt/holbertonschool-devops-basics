package main

import (
	"log"
	"net/http"

	"example.com/inventory-api/internal/api"
)

func main() {
	server := &http.Server{
		Addr:    ":8080",
		Handler: api.Handler(),
	}
	log.Fatal(server.ListenAndServe())
}
