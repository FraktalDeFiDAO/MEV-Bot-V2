// FILE: internal/rpc/server.go

package rpc

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"
)

type RPCRequest struct {
	ID      string          `json:"id"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params"`
	JSONRPC string          `json:"jsonrpc"`
}

type RPCResponse struct {
	ID      string      `json:"id"`
	Result  interface{} `json:"result,omitempty"`
	Error   interface{} `json:"error,omitempty"`
	JSONRPC string      `json:"jsonrpc"`
}

type HandlerFunc func(params json.RawMessage) (interface{}, error)

type Server struct {
	handlers map[string]HandlerFunc
	mu       sync.RWMutex
}

func NewServer() *Server {
	return &Server{
		handlers: make(map[string]HandlerFunc),
	}
}

func (s *Server) Register(method string, handler HandlerFunc) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.handlers[method] = handler
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	var req RPCRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request", http.StatusBadRequest)
		return
	}

	s.mu.RLock()
	handler, ok := s.handlers[req.Method]
	s.mu.RUnlock()

	resp := RPCResponse{ID: req.ID, JSONRPC: "2.0"}

	if !ok {
		resp.Error = "Method not found"
	} else {
		result, err := handler(req.Params)
		if err != nil {
			resp.Error = err.Error()
		} else {
			resp.Result = result
		}
	}

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(resp); err != nil {
		log.Println("Failed to encode response:", err)
	}
}
