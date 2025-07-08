// =================================================================
// FILE: config/config.go
// =================================================================
// This new file handles all configuration loading using viper.
package config

import (
	"log"
	"strings"

	"github.com/spf13/viper"
)

// Config stores all configuration for the application.
// The values are read by viper from a config file and/or environment variables.
type Config struct {
	EthRPCURL          string `mapstructure:"ETH_RPC_URL"`
	ExecutorPrivateKey string `mapstructure:"EXECUTOR_PRIVATE_KEY"`
	DatabasePath       string `mapstructure:"DATABASE_PATH"`
}

// LoadConfig reads configuration from file and environment variables.
func LoadConfig() (config Config, err error) {
	// --- Set up Viper ---

	// Set the file path for the configuration file.
	viper.AddConfigPath("./config") // Look for config file in the ./config/ directory
	viper.SetConfigName("config")   // Name of config file (without extension)
	viper.SetConfigType("yaml")     // Type of the config file

	// --- Set up Environment Variable Handling ---

	// Automatically read environment variables that match keys.
	viper.AutomaticEnv()
	// Replace dots with underscores in env var names (e.g., app.port -> APP_PORT)
	viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))

	// --- Read Configuration ---

	// Attempt to read the config file. It's okay if it doesn't exist.
	if err = viper.ReadInConfig(); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); ok {
			// Config file not found; ignore error if this is expected
			log.Println("Configuration file not found, relying on environment variables.")
		} else {
			// Config file was found but another error was produced
			return
		}
	}

	// --- Unmarshal the configuration into the struct ---
	err = viper.Unmarshal(&config)
	if err != nil {
		log.Fatalf("Unable to decode into struct, %v", err)
		return
	}

	// --- Validate Critical Configuration ---
	// Ensure the private key is provided, as the application cannot run without it.
	if config.ExecutorPrivateKey == "" {
		log.Fatal("CRITICAL: EXECUTOR_PRIVATE_KEY environment variable is not set.")
	}

	// Hide the private key from any logs for security.
	log.Println("Configuration loaded successfully.")
	log.Printf("Using ETH RPC URL: %s", config.EthRPCURL)

	return
}


// =================================================================
// FILE: App/App.go (EXAMPLE USAGE)
// =================================================================
// An example of how you would use the new LoadConfig function in your main app setup.

package App

import (
	"context"
	"log"

	// Import the new config package
	"fraktal/mev-bot-v2/config"

	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	// ... other imports
)

// ... (keep your existing App struct)

// NewApp initializes the application and all its constituent services.
func NewApp() (*App, error) {
	// Load configuration first
	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Initialize Ethereum client using the URL from config
	ethClient, err := ethclient.Dial(cfg.EthRPCURL)
	if err != nil {
		log.Fatalf("Failed to connect to Ethereum client: %v", err)
	}

	// Example of using the private key securely from config
	// NOTE: This part is for demonstration. Your Executor service would handle this.
	privateKey, err := crypto.HexToECDSA(cfg.ExecutorPrivateKey)
	if err != nil {
		log.Fatalf("Failed to parse executor private key: %v", err)
	}
	// Now you can use the 'privateKey' object to sign transactions.

	// ... rest of your application setup using cfg values
	// For example, when initializing the Database service:
	// dbService := Database.NewService(cfg.DatabasePath)

	log.Println("Application initialized successfully.")
	// ...
	return &App{/* ... */}, nil
}
