package Dispatcher

import (
	"encoding/json"
	"fraktal/mev-bot-v2/Database" // Import the Database package to use its Opportunity struct
	"log"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
)

// The Opportunity struct is now defined in the Database package.
// This avoids type conflicts and creates a single source of truth.

// Hub manages WebSocket connections and broadcasts messages.
type Hub struct {
	clients    map[*websocket.Conn]bool
	broadcast  chan []byte
	register   chan *websocket.Conn
	unregister chan *websocket.Conn
	mu         sync.Mutex
}

// NewHub creates a new Hub.
func NewHub() *Hub {
	return &Hub{
		broadcast:  make(chan []byte),
		register:   make(chan *websocket.Conn),
		unregister: make(chan *websocket.Conn),
		clients:    make(map[*websocket.Conn]bool),
	}
}

// Run starts the Hub's main loop for managing clients and messages.
func (h *Hub) Run() {
	for {
		select {
		case conn := <-h.register:
			h.mu.Lock()
			h.clients[conn] = true
			h.mu.Unlock()
			log.Println("Dispatcher: Client connected.")
		case conn := <-h.unregister:
			h.mu.Lock()
			if _, ok := h.clients[conn]; ok {
				delete(h.clients, conn)
				conn.Close()
				log.Println("Dispatcher: Client disconnected.")
			}
			h.mu.Unlock()
		case message := <-h.broadcast:
			h.mu.Lock()
			for conn := range h.clients {
				if err := conn.WriteMessage(websocket.TextMessage, message); err != nil {
					log.Printf("Dispatcher: Write error: %v", err)
					// If a write fails, assume the client is disconnected and unregister it.
					go func(c *websocket.Conn) { h.unregister <- c }(conn)
				}
			}
			h.mu.Unlock()
		}
	}
}

// BroadcastOpportunity now accepts the canonical *Database.Opportunity type.
func (h *Hub) BroadcastOpportunity(op *Database.Opportunity) {
	op.Type = "ARBITRAGE_OPPORTUNITY"
	message, err := json.Marshal(op)
	if err != nil {
		log.Printf("Dispatcher: Error marshalling opportunity: %v", err)
		return
	}
	h.broadcast <- message
}

// upgrader is used to upgrade HTTP connections to WebSocket connections.
var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true }, // Allow all origins for simplicity.
}

// ServeWs handles incoming WebSocket connection requests.
func (h *Hub) ServeWs(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("ServeWs upgrade error:", err)
		return
	}
	// Register the new connection with the hub.
	h.register <- conn
}
