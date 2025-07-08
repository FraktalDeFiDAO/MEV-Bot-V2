package main

import (
	"flag"
	"fmt"
	"fraktal/mev-bot-v2/App"
	"fraktal/mev-bot-v2/Cache"
	"fraktal/mev-bot-v2/Client"
	"fraktal/mev-bot-v2/Database"
	"fraktal/mev-bot-v2/Discovery"
	"fraktal/mev-bot-v2/Dispatcher"
	"fraktal/mev-bot-v2/Executor"
	"fraktal/mev-bot-v2/Multicall"
	"fraktal/mev-bot-v2/Updater"
	"fraktal/mev-bot-v2/config"
	"log"
	"net/http"
	"os"

	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/joho/godotenv"
)

func main() {
	err := godotenv.Load()
	if err != nil {
		log.Println("No .env file found, using environment variables or flags")
	}

	mode := flag.String("mode", "dispatcher", "Run mode: 'dispatcher' or 'executor'")
	dispatcherAddr := flag.String("dispatcher-addr", "localhost:8080", "Address for the dispatcher server or executor connection")
	flag.Parse()

	fmt.Printf("Fraktal MEV Bot :: Mode: %s\n", *mode)

	if *mode == "dispatcher" {
		runDispatcher(*dispatcherAddr)
	} else if *mode == "executor" {
		runExecutor(*dispatcherAddr)
	} else {
		log.Fatalf("Invalid mode: %s. Use 'dispatcher' or 'executor'.", *mode)
	}
}

func runDispatcher(addr string) {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("FATAL: Failed to load config: %v", err)
	}

	log.Printf("Connecting to %s...", cfg.ArbitrumRPCURLWS)
	ethClient, err := ethclient.Dial(cfg.ArbitrumRPCURLWS)
	if err != nil {
		log.Fatalf("FATAL: Error setting eth client: %v\n", err)
	}

	// --- Initialize all services ---
	hub := Dispatcher.NewHub()
	cache := Cache.New()
	dbService, err := Database.NewDBService(cfg.DBPath)
	if err != nil {
		log.Fatalf("FATAL: Error creating DB service: %v", err)
	}
	mcService, err := Multicall.NewMulticallService(cfg.ArbitrumRPCURLHTTP)
	if err != nil {
		log.Fatalf("FATAL: Error creating Multicall service: %v", err)
	}

	// Create a buffered channel for the discovery queue
	discoveryQueue := make(chan App.PoolToDiscover, 1000)

	// The App gets the write-end of the channel.
	app, err := App.NewApp(ethClient, cfg.ArbitrumRPCURLHTTP, hub, cache, dbService, mcService, discoveryQueue)
	if err != nil {
		log.Fatalf("FATAL: Error instantiating app: %v", err)
	}

	// The Discovery service gets the App reference and the read-end of the channel.
	discoveryService := Discovery.New(app, discoveryQueue)
	updater := Updater.New(cache, mcService)

	// --- Start all services ---
	go hub.Run()
	go app.Run()
	go updater.Run()
	go discoveryService.Run()

	http.HandleFunc("/ws", hub.ServeWs)
	log.Printf("Dispatcher listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}

func runExecutor(dispatcherAddr string) {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("FATAL: Failed to load config: %v", err)
	}

	if cfg.ExecutorPrivateKey == "" {
		log.Fatal("FATAL: EXECUTOR_PRIVATE_KEY not set in .env for executor mode")
	}
	if cfg.DiamondAddress == "" {
		log.Fatal("FATAL: DIAMOND_ADDRESS not set in .env for executor mode")
	}

	// Initialize the executor service
	executorService, err := Executor.New(cfg)
	if err != nil {
		log.Fatalf("FATAL: Failed to initialize executor service: %v", err)
	}

	wsURL := "ws://" + dispatcherAddr + "/ws"
	// The client now takes the executor service to act on opportunities
	client := Client.NewArbitrageClient(wsURL, executorService)
	client.Run()
}
