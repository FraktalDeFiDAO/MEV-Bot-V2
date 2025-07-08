package blockchain

import (
	"context"
	"log"
	"math/big"
	"strings"
	"time"

	"fraktal/mev-bot-v2/uniswap" // Adjusted module path

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
)

func ListenV2FactoryEvents(
	ctx context.Context,
	client *ethclient.Client,
	factoryAddress common.Address, // Now primarily for logging/context if a specific one was known/configured
	newPoolChan chan<- *uniswap.NewPoolNotification,
	historicalSyncStartBlock uint64,
) {
	// If factoryAddress is zero, it implies no specific factory was targeted for logging.
	logContext := "Global Scan"
	if factoryAddress != (common.Address{}) {
		logContext = "Global Scan (context factory: " + factoryAddress.Hex() + ")"
	}
	log.Printf("V2 Factory Listener: Starting. Mode: %s for PairCreated events.", logContext)

	// query for historical scan - Addresses field is omitted for global scan
	historicalQuery := ethereum.FilterQuery{
		// Addresses: nil, // Omitted: scan all addresses
		Topics: [][]common.Hash{{uniswap.PairCreatedEvent}},
	}
	if historicalSyncStartBlock > 0 {
		historicalQuery.FromBlock = new(big.Int).SetUint64(historicalSyncStartBlock)
		log.Printf("V2 Factory Listener: Scanning for historical PairCreated events from block %d.", historicalSyncStartBlock)
	} else {
		log.Printf("V2 Factory Listener: historicalSyncStartBlock is 0. Historical scan might be from genesis or not run, depending on node interpretation of nil FromBlock for FilterLogs.")
		// For many nodes, nil FromBlock in FilterLogs means from genesis. Be specific with start blocks.
	}

	// Historical Scan
	if historicalQuery.FromBlock != nil || historicalSyncStartBlock == 0 { // Attempt scan if start block is non-zero, or if zero (might mean genesis)
		scanCtx, scanCancel := context.WithTimeout(context.Background(), 15*time.Minute) // Increased timeout for potentially large global scan
		pastLogs, err := client.FilterLogs(scanCtx, historicalQuery)
		scanCancel()
		if err != nil {
			log.Printf("V2 Factory Listener: Error fetching historical PairCreated events (%s): %v", logContext, err)
		} else {
			log.Printf("V2 Factory Listener: Found %d historical PairCreated events (%s) since block %v.", len(pastLogs), logContext, historicalQuery.FromBlock)
			for _, vLog := range pastLogs {
				if vLog.Removed {
					continue
				}
				event, err := uniswap.ParseV2PairCreated(vLog)
				if err != nil {
					log.Printf("V2 Factory Listener: Error parsing historical PairCreated event (Tx: %s, %s): %v", vLog.TxHash.Hex(), logContext, err)
					continue
				}
				log.Printf("V2 Factory Listener: Historical V2 Pair: %s (T0: %s, T1: %s) at block %d from global scan.", event.Pair.Hex(), event.Token0.Hex(), event.Token1.Hex(), vLog.BlockNumber)
				select {
				case newPoolChan <- &uniswap.NewPoolNotification{
					Address:     event.Pair,
					Protocol:    uniswap.V2,
					Token0:      event.Token0,
					Token1:      event.Token1,
					BlockNumber: vLog.BlockNumber,
					TxHash:      vLog.TxHash,
				}:
				case <-ctx.Done():
					log.Printf("V2 Factory Listener: Context cancelled during historical processing (%s). Stopping.", logContext)
					return
				}
			}
		}
	}

	// Real-time Subscription - Addresses field is omitted for global scan
	logs := make(chan types.Log, 100)
	liveQuery := ethereum.FilterQuery{
		// Addresses: nil, // Omitted: scan all addresses
		Topics: [][]common.Hash{{uniswap.PairCreatedEvent}},
	}

	subAttemptCtx, subAttemptCancel := context.WithCancel(ctx)
	var sub ethereum.Subscription
	var subErr error

	go func() {
		defer subAttemptCancel()
		for {
			select {
			case <-subAttemptCtx.Done():
				return
			default:
			}
			log.Printf("V2 Factory Listener: Attempting to subscribe to new PairCreated events (Global Scan).")
			currentSub, currentErr := client.SubscribeFilterLogs(subAttemptCtx, liveQuery, logs)
			if currentErr != nil {
				log.Printf("V2 Factory Listener: Failed to subscribe to PairCreated events (Global Scan): %v. Retrying in 10s.", currentErr)
				select {
				case <-time.After(10 * time.Second):
					continue
				case <-subAttemptCtx.Done():
					subErr = currentErr
					return
				}
			}
			log.Printf("V2 Factory Listener: Subscribed to new PairCreated events (Global Scan).")
			sub = currentSub
			return
		}
	}()

	<-subAttemptCtx.Done()
	if sub == nil {
		if ctx.Err() != nil {
			log.Printf("V2 Factory Listener: Subscription cancelled by parent context (Global Scan).")
		} else {
			log.Printf("V2 Factory Listener: Failed to establish subscription (Global Scan) after attempts: %v. Listener will not run for new events.", subErr)
		}
		return
	}
	defer sub.Unsubscribe()

	log.Printf("V2 Factory Listener: Now listening for live PairCreated events (Global Scan).")
	for {
		select {
		case <-ctx.Done():
			log.Printf("V2 Factory Listener: Context cancelled (Global Scan), shutting down.")
			return
		case err := <-sub.Err():
			log.Printf("V2 Factory Listener: Subscription error (Global Scan): %v. Listener will terminate.", err)
			return
		case vLog := <-logs:
			if vLog.Removed {
				log.Printf("V2 Factory Listener: PairCreated log (Tx: %s, Global Scan) removed by reorg.", vLog.TxHash.Hex())
				continue
			}
			event, err := uniswap.ParseV2PairCreated(vLog)
			if err != nil {
				log.Printf("V2 Factory Listener: Error parsing live PairCreated event (Tx: %s, Global Scan): %v", vLog.TxHash.Hex(), err)
				continue
			}
			log.Printf("V2 Factory Listener: New V2 Pair Discovered (Global Scan): %s (T0: %s, T1: %s) at block %d. Originating Contract: %s",
				strings.ToLower(event.Pair.Hex()), strings.ToLower(event.Token0.Hex()), strings.ToLower(event.Token1.Hex()), vLog.BlockNumber, vLog.Address.Hex())

			select {
			case newPoolChan <- &uniswap.NewPoolNotification{
				Address:     event.Pair, // This is the address of the newly created pair contract
				Protocol:    uniswap.V2,
				Token0:      event.Token0,
				Token1:      event.Token1,
				BlockNumber: vLog.BlockNumber,
				TxHash:      vLog.TxHash,
			}:
			case <-ctx.Done():
				log.Printf("V2 Factory Listener: Context cancelled while sending new V2 pair (Global Scan). Shutting down.")
				return
			}
		}
	}
}
