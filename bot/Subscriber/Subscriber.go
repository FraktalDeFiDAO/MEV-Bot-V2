package Subscriber

import (
	"context"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
)

// Subscription function now accepts a slice of event topic hashes.
func Subscription(
	client *ethclient.Client,
	logs chan types.Log,
	eventTopics []common.Hash,
) (ethereum.Subscription, error) {
	// The query now includes all topics passed to the function.
	// This creates an "OR" condition for the event signatures.
	query := ethereum.FilterQuery{
		Topics: [][]common.Hash{eventTopics},
	}

	// Use an inner buffered channel to prevent blocking the underlying subscription
	inner := make(chan types.Log, 100)
	sub, err := client.SubscribeFilterLogs(context.Background(), query, inner)
	if err != nil {
		return nil, err
	}

	// Forward logs non-blocking to external channel, dropping if full
	go func() {
		for vLog := range inner {
			select {
			case logs <- vLog:
			default:
				// drop log to avoid backpressure
			}
		}
	}()

	return sub, nil
}
