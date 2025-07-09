package main

import (
	"flag"
	"fmt"
	"fraktal/mev-bot-v2/App"
	"fraktal/mev-bot-v2/Cache"
	"fraktal/mev-bot-v2/Client"
	"fraktal/mev-bot-v2/Database"
	"fraktal/mev-bot-v2/Debug"
	"fraktal/mev-bot-v2/Discovery"
	"fraktal/mev-bot-v2/Dispatcher"
	"fraktal/mev-bot-v2/EventRouter"
	"fraktal/mev-bot-v2/Executor"
	"fraktal/mev-bot-v2/Market"
	"fraktal/mev-bot-v2/Multicall"
	"fraktal/mev-bot-v2/Parser"
	"fraktal/mev-bot-v2/Scanner"
	"fraktal/mev-bot-v2/Updater"
	"fraktal/mev-bot-v2/config"
	"log"
	"net/http"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/joho/godotenv"
)

func main() {
	err := godotenv.Load()
	if err != nil {
		log.Println("Warning: .env file not found, relying on environment variables.")
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

// runDispatcher starts the main MEV bot application.
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

	// --- Initialize Core Services & Utilities ---
	hub := Dispatcher.NewHub()
	cache := Cache.New()
	dbWriter, err := Database.NewDBWriter(cfg.DBPath)
	if err != nil {
		log.Fatalf("FATAL: Error creating DBWriter service: %v", err)
	}
	debugLogger, err := Debug.NewLogger("logs/debug.log")
	if err != nil {
		log.Fatalf("FATAL: Error creating DebugLogger: %v", err)
	}
	defer debugLogger.Close()

	mcService, err := Multicall.NewMulticallService(cfg.ArbitrumRPCURLHTTP)
	if err != nil {
		log.Fatalf("FATAL: Error creating Multicall service: %v", err)
	}
	parserService, err := Parser.NewService()
	if err != nil {
		log.Fatalf("FATAL: Error creating Parser service: %v", err)
	}
	discoveryQueue := make(chan common.Address, 1000)

	// --- Initialize Application Services with Corrected Dependencies ---
	scannerService := Scanner.NewService(cache, hub, dbWriter.WriteQueue)
	marketService := Market.NewService(cache, scannerService, parserService, dbWriter.WriteQueue, debugLogger)
	discoveryService, err := Discovery.NewService(&cfg, ethClient, mcService, cache, marketService, discoveryQueue, dbWriter.WriteQueue)
	if err != nil {
		log.Fatalf("FATAL: Error creating Discovery service: %v", err)
	}
	// CORRECTED: Updater interval changed to 10 seconds.
	updaterService := Updater.New(cache, mcService, 10*time.Second)
	eventRouter := EventRouter.NewService(cache, marketService, discoveryService)

	// --- Initialize the App Orchestrator ---
	app, err := App.NewApp(ethClient, cache, marketService, discoveryService, eventRouter, dbWriter)
	if err != nil {
		log.Fatalf("FATAL: Error instantiating app: %v", err)
	}

	// --- Start all background services as goroutines ---
	go dbWriter.Run() // Start the database writer
	go hub.Run()
	go app.Run()
	go updaterService.Run()
	go discoveryService.Run()

	// Start the WebSocket server.
	http.HandleFunc("/ws", hub.ServeWs)
	log.Printf("Dispatcher listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}

// runExecutor starts the client that connects to the dispatcher and executes trades.
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

	executorService, err := Executor.New(cfg)
	if err != nil {
		log.Fatalf("FATAL: Failed to initialize executor service: %v", err)
	}

	wsURL := "ws://" + dispatcherAddr + "/ws"
	client := Client.NewArbitrageClient(wsURL, executorService)
	client.Run()
}
