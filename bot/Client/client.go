package Client

import (
	"encoding/json"
	"fraktal/mev-bot-v2/Database" // Import the Database package
	"fraktal/mev-bot-v2/Executor"
	"log"
	"net/url"
	"time"

	"github.com/gorilla/websocket"
)

// ArbitrageClient connects to the Dispatcher WebSocket and hands off opportunities to the Executor.
type ArbitrageClient struct {
	dispatcherURL string
	executor      *Executor.Executor // The executor service that will process opportunities.
}

// NewArbitrageClient creates a new client.
func NewArbitrageClient(dispatcherURL string, executor *Executor.Executor) *ArbitrageClient {
	return &ArbitrageClient{
		dispatcherURL: dispatcherURL,
		executor:      executor,
	}
}

// Run starts the client's connection and message handling loop.
func (c *ArbitrageClient) Run() {
	u, err := url.Parse(c.dispatcherURL)
	if err != nil {
		log.Fatalf("Executor: invalid dispatcher URL: %v", err)
	}

	var reconnectDelay = 1 * time.Second

	// Infinite loop to handle connections and reconnections.
	for {
		log.Printf("Executor: Attempting to connect to %s", u.String())
		conn, _, err := websocket.DefaultDialer.Dial(u.String(), nil)
		if err != nil {
			log.Printf("Executor: Dial error to %s: %v", c.dispatcherURL, err)
			log.Printf("Executor: Reconnecting in %s...", reconnectDelay)
			time.Sleep(reconnectDelay)
			// Implement exponential backoff for reconnection attempts.
			reconnectDelay *= 2
			if reconnectDelay > 60*time.Second {
				reconnectDelay = 60 * time.Second
			}
			continue
		}

		log.Println("Executor: Successfully connected to dispatcher.")
		reconnectDelay = 1 * time.Second // Reset reconnect delay on successful connection.

		// Loop to read messages from the WebSocket.
		for {
			_, message, err := conn.ReadMessage()
			if err != nil {
				log.Println("Executor: Read error (connection lost):", err)
				conn.Close()
				break // Break inner loop to trigger reconnection.
			}

			// Use the canonical Database.Opportunity struct for unmarshalling.
			var op Database.Opportunity
			if err := json.Unmarshal(message, &op); err != nil {
				log.Printf("Executor: Unmarshal error: %v", err)
				continue
			}

			// Check if the message is an arbitrage opportunity.
			if op.Type == "ARBITRAGE_OPPORTUNITY" {
				log.Printf(">> EXECUTOR RECEIVED ARB OPP for %s (%.4f%% profit)", op.SymbolTicker, op.PercentDiff)

				// Hand off the opportunity to the executor service.
				// Run in a goroutine to avoid blocking the WebSocket read loop.
				if c.executor != nil {
					go c.executor.Execute(op)
				} else {
					log.Println("Executor service not initialized, cannot execute.")
				}
			}
		}
	}
}
