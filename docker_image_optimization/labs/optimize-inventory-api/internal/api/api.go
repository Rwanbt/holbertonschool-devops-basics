package api

import (
	"encoding/json"
	"net/http"
)

type item struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
}

func Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{
			"service": "inventory-api",
			"status":  "ok",
		})
	})
	mux.HandleFunc("/items", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string][]item{
			"items": {
				{ID: 1, Name: "layers"},
				{ID: 2, Name: "cache"},
			},
		})
	})
	return mux
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}
