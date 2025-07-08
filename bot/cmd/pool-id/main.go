package main

import (
	"context"
	"flag"
	"fmt"
	"fraktal/mev-bot-v2/config"
	"fraktal/mev-bot-v2/contracts/bindings/pooltypechecker"
	"fraktal/mev-bot-v2/uniswap" // Import the uniswap package
	"log"
	"os"
	"sync"

	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
)

// mapPoolTypeToString converts the contract's enum (uint8) to a readable string.
func mapPoolTypeToString(poolType uint8) string {
	switch poolType {
	case uniswap.PoolTypeNONE:
		return "NONE"
	case uniswap.PoolTypeUNISWAPV2:
		return "\033[34mUniswap V2\033[0m"
	case uniswap.PoolTypeUNISWAPV3:
		return "\033[32mUniswap V3\033[0m"
	case uniswap.PoolTypeALGEBRAV1:
		return "\033[33mAlgebra V1 (Static Fee)\033[0m"
	case uniswap.PoolTypeALGEBRAV1ADAPTIVE: // ADDED
		return "\033[33mAlgebra V1 (Adaptive Fee)\033[0m"
	case uniswap.PoolTypeALGEBRAV1DBF:
		return "\033[33mAlgebra V1 (Directional Fee)\033[0m"
	case uniswap.PoolTypeALGEBRAV2DBF:
		return "\033[33mAlgebra V2 (Directional Fee)\033[0m"
	default:
		return fmt.Sprintf("Unknown Type (%d)", poolType)
	}
}

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("FATAL: Failed to load config: %v", err)
	}
	if cfg.PoolTypeCheckerAddress == "" || !common.IsHexAddress(cfg.PoolTypeCheckerAddress) {
		log.Fatal("FATAL: POOL_TYPE_CHECKER_ADDRESS is not set or invalid in your .env file.")
	}

	flag.Parse()
	addresses := flag.Args()
	if len(addresses) == 0 {
		fmt.Println("Usage: go run ./cmd/pool-id/main.go <address1> <address2> ...")
		os.Exit(1)
	}

	client, err := ethclient.Dial(cfg.ArbitrumRPCURLHTTP)
	if err != nil {
		log.Fatalf("FATAL: Failed to connect to Ethereum client: %v", err)
	}

	checkerAddress := common.HexToAddress(cfg.PoolTypeCheckerAddress)
	checker, err := pooltypechecker.NewPoolTypeChecker(checkerAddress, client)
	if err != nil {
		log.Fatalf("FATAL: Failed to instantiate PoolTypeChecker contract: %v", err)
	}

	var wg sync.WaitGroup
	results := make(chan string, len(addresses))

	fmt.Println("Starting pool identification using on-chain PoolTypeChecker...")

	for _, addrStr := range addresses {
		if !common.IsHexAddress(addrStr) {
			results <- fmt.Sprintf("Address: %s -> \033[31mError: Invalid Ethereum address\033[0m", addrStr)
			continue
		}
		wg.Add(1)
		go func(addr common.Address) {
			defer wg.Done()
			poolType, err := checker.CheckPoolType(&bind.CallOpts{Context: context.Background()}, addr)
			if err != nil {
				results <- fmt.Sprintf("Address: %s -> \033[31mError checking type: %v\033[0m", addr.Hex(), err)
				return
			}
			results <- fmt.Sprintf("Address: %s -> Type: %s", addr.Hex(), mapPoolTypeToString(poolType))
		}(common.HexToAddress(addrStr))
	}

	wg.Wait()
	close(results)
	for result := range results {
		fmt.Println(result)
	}
}
