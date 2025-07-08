package blockchain

import (
	"context"
	"log"
	"time"

	"github.com/ethereum/go-ethereum/ethclient"
)

func Connect(rpcURL string) (*ethclient.Client, error) {
	var client *ethclient.Client
	var err error
	maxRetries := 5
	retryDelay := 5 * time.Second

	for i := 0; i < maxRetries; i++ {
		client, err = ethclient.Dial(rpcURL)
		if err == nil {
			// Verify connection by getting chain ID
			chainIDCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			_, chainErr := client.ChainID(chainIDCtx)
			if chainErr != nil {
				log.Printf("Failed to get chain ID after connecting to %s, retrying (%d/%d): %v", rpcURL, i+1, maxRetries, chainErr)
				client.Close()
				client = nil // Ensure client is nil for next attempt
				time.Sleep(retryDelay)
				continue
			}
			log.Println("Successfully connected to Ethereum client:", rpcURL)
			return client, nil
		}
		log.Printf("Failed to connect to Ethereum client (%s), retrying (%d/%d) in %s: %v", rpcURL, i+1, maxRetries, retryDelay, err)
		time.Sleep(retryDelay)
	}
	return nil, err // Return last error after all retries
}
