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

func ListenV3FactoryEvents(
	ctx context.Context,
	client *ethclient.Client,
	factoryAddress common.Address, // Now primarily for logging/context
	newPoolChan chan<- *uniswap.NewPoolNotification,
	historicalSyncStartBlock uint64,
) {
	logContext := "Global Scan"
	if factoryAddress != (common.Address{}) {
		logContext = "Global Scan (context factory: " + factoryAddress.Hex() + ")"
	}
	log.Printf("V3 Factory Listener: Starting. Mode: %s for PoolCreated events.", logContext)

	// query for historical scan - Addresses field is omitted for global scan
	historicalQuery := ethereum.FilterQuery{
		// Addresses: nil, // Omitted: scan all addresses
		Topics: [][]common.Hash{{uniswap.PoolCreatedEvent}},
	}
	if historicalSyncStartBlock > 0 {
		historicalQuery.FromBlock = new(big.Int).SetUint64(historicalSyncStartBlock)
		log.Printf("V3 Factory Listener: Scanning for historical PoolCreated events from block %d.", historicalSyncStartBlock)
	} else {
		log.Printf("V3 Factory Listener: historicalSyncStartBlock is 0. Historical scan might be from genesis or not run.")
	}

	// Historical Scan
	if historicalQuery.FromBlock != nil || historicalSyncStartBlock == 0 {
		scanCtx, scanCancel := context.WithTimeout(context.Background(), 15*time.Minute) // Increased timeout
		pastLogs, err := client.FilterLogs(scanCtx, historicalQuery)
		scanCancel()
		if err != nil {
			log.Printf("V3 Factory Listener: Error fetching historical PoolCreated events (%s): %v", logContext, err)
		} else {
			log.Printf("V3 Factory Listener: Found %d historical PoolCreated events (%s) since block %v.", len(pastLogs), logContext, historicalQuery.FromBlock)
			for _, vLog := range pastLogs {
				if vLog.Removed {
					continue
				}
				event, err := uniswap.ParseV3PoolCreated(vLog)
				if err != nil {
					log.Printf("V3 Factory Listener: Error parsing historical PoolCreated event (Tx: %s, %s): %v", vLog.TxHash.Hex(), logContext, err)
					continue
				}
				log.Printf("V3 Factory Listener: Historical V3 Pool: %s (T0: %s, T1: %s, Fee: %s) at block %d from global scan.", event.Pool.Hex(), event.Token0.Hex(), event.Token1.Hex(), event.Fee.String(), vLog.BlockNumber)
				select {
				case newPoolChan <- &uniswap.NewPoolNotification{
					Address:     event.Pool,
					Protocol:    uniswap.V3,
					Token0:      event.Token0,
					Token1:      event.Token1,
					Fee:         event.Fee,
					BlockNumber: vLog.BlockNumber,
					TxHash:      vLog.TxHash,
				}:
				case <-ctx.Done():
					log.Printf("V3 Factory Listener: Context cancelled during historical processing (%s). Stopping.", logContext)
					return
				}
			}
		}
	}

	// Real-time Subscription - Addresses field is omitted for global scan
	logs := make(chan types.Log, 100)
	liveQuery := ethereum.FilterQuery{
		// Addresses: nil, // Omitted: scan all addresses
		Topics: [][]common.Hash{{uniswap.PoolCreatedEvent}},
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
			log.Printf("V3 Factory Listener: Attempting to subscribe to new PoolCreated events (Global Scan).")
			currentSub, currentErr := client.SubscribeFilterLogs(subAttemptCtx, liveQuery, logs)
			if currentErr != nil {
				log.Printf("V3 Factory Listener: Failed to subscribe to PoolCreated events (Global Scan): %v. Retrying in 10s.", currentErr)
				select {
				case <-time.After(10 * time.Second):
					continue
				case <-subAttemptCtx.Done():
					subErr = currentErr
					return
				}
			}
			log.Printf("V3 Factory Listener: Subscribed to new PoolCreated events (Global Scan).")
			sub = currentSub
			return
		}
	}()

	<-subAttemptCtx.Done()
	if sub == nil {
		if ctx.Err() != nil {
			log.Printf("V3 Factory Listener: Subscription cancelled by parent context (Global Scan).")
		} else {
			log.Printf("V3 Factory Listener: Failed to establish subscription (Global Scan) after attempts: %v. Listener will not run for new events.", subErr)
		}
		return
	}
	defer sub.Unsubscribe()

	log.Printf("V3 Factory Listener: Now listening for live PoolCreated events (Global Scan).")
	for {
		select {
		case <-ctx.Done():
			log.Printf("V3 Factory Listener: Context cancelled (Global Scan), shutting down.")
			return
		case err := <-sub.Err():
			log.Printf("V3 Factory Listener: Subscription error (Global Scan): %v. Listener will terminate.", err)
			return
		case vLog := <-logs:
			if vLog.Removed {
				log.Printf("V3 Factory Listener: PoolCreated log (Tx: %s, Global Scan) removed by reorg.", vLog.TxHash.Hex())
				continue
			}
			event, err := uniswap.ParseV3PoolCreated(vLog)
			if err != nil {
				log.Printf("V3 Factory Listener: Error parsing live PoolCreated event (Tx: %s, Global Scan): %v", vLog.TxHash.Hex(), err)
				continue
			}
			log.Printf("V3 Factory Listener: New V3 Pool Discovered (Global Scan): %s (T0: %s, T1: %s, Fee: %s) at block %d. Originating Contract: %s",
				strings.ToLower(event.Pool.Hex()), strings.ToLower(event.Token0.Hex()), strings.ToLower(event.Token1.Hex()), event.Fee.String(), vLog.BlockNumber, vLog.Address.Hex())

			select {
			case newPoolChan <- &uniswap.NewPoolNotification{
				Address:     event.Pool, // This is the address of the newly created pool contract
				Protocol:    uniswap.V3,
				Token0:      event.Token0,
				Token1:      event.Token1,
				Fee:         event.Fee,
				BlockNumber: vLog.BlockNumber,
				TxHash:      vLog.TxHash,
			}:
			case <-ctx.Done():
				log.Printf("V3 Factory Listener: Context cancelled while sending new V3 pool (Global Scan). Shutting down.")
				return
			}
		}
	}
}
