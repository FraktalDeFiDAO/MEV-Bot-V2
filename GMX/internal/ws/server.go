// FILE: internal/ws/server.go

package ws

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
)

type Message struct {
	Type string      `json:"type"`
	Data interface{} `json:"data"`
}

type Client struct {
	Conn *websocket.Conn
	Send chan Message
}

type Hub struct {
	Clients    map[*Client]bool
	Broadcast  chan Message
	Register   chan *Client
	Unregister chan *Client
	mu         sync.Mutex
}

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

func NewHub() *Hub {
	return &Hub{
		Clients:    make(map[*Client]bool),
		Broadcast:  make(chan Message),
		Register:   make(chan *Client),
		Unregister: make(chan *Client),
	}
}

func (h *Hub) Run() {
	for {
		select {
		case client := <-h.Register:
			h.mu.Lock()
			h.Clients[client] = true
			h.mu.Unlock()
		case client := <-h.Unregister:
			h.mu.Lock()
			if _, ok := h.Clients[client]; ok {
				delete(h.Clients, client)
				close(client.Send)
			}
			h.mu.Unlock()
		case message := <-h.Broadcast:
			h.mu.Lock()
			for client := range h.Clients {
				select {
				case client.Send <- message:
				default:
					close(client.Send)
					delete(h.Clients, client)
				}
			}
			h.mu.Unlock()
		}
	}
}

func ServeWS(hub *Hub, w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("WebSocket upgrade error:", err)
		return
	}
	client := &Client{Conn: conn, Send: make(chan Message)}
	hub.Register <- client

	go client.writePump()
	go client.readPump(hub)
}

func (c *Client) readPump(hub *Hub) {
	defer func() {
		hub.Unregister <- c
		c.Conn.Close()
	}()
	for {
		_, msg, err := c.Conn.ReadMessage()
		if err != nil {
			break
		}
		var m Message
		if err := json.Unmarshal(msg, &m); err == nil {
			// Future: handle message types, authentication, etc.
			hub.Broadcast <- m
		}
	}
}

func (c *Client) writePump() {
	for msg := range c.Send {
		if err := c.Conn.WriteJSON(msg); err != nil {
			break
		}
	}
	c.Conn.Close()
}
