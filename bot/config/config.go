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
	EthRPCURL               string   `mapstructure:"ETH_RPC_URL"`
	ExecutorPrivateKey      string   `mapstructure:"EXECUTOR_PRIVATE_KEY"`
	DatabasePath            string   `mapstructure:"DATABASE_PATH"`
	DBPath                  string   `mapstructure:"DB_PATH"`
	ArbitrumRPCURLWS        string   `mapstructure:"ARBITRUM_RPC_URL_WS"`
	ArbitrumRPCURLHTTP      string   `mapstructure:"ARBITRUM_RPC_URL_HTTP"`
	ArbitrumRPCURL          string   `mapstructure:"ARBITRUM_RPC_URL"`
	MulticallAddress        string   `mapstructure:"MULTICALL_ADDRESS"`
	DiamondAddress          string   `mapstructure:"DIAMOND_ADDRESS"`
	PoolTypeCheckerAddress  string   `mapstructure:"POOL_TYPE_CHECKER_ADDRESS"`
	DBType                  string   `mapstructure:"DB_TYPE"`
	DBDsn                   string   `mapstructure:"DB_DSN"`
	TrackedV2Pairs          []string `mapstructure:"TRACKED_V2_PAIRS"`
	TrackedV3Pools          []string `mapstructure:"TRACKED_V3_POOLS"`
	LogProcessedEvents      bool     `mapstructure:"LOG_PROCESSED_EVENTS"`
	StartBlock              uint64   `mapstructure:"START_BLOCK"`
	DiscoverV2Pools         bool     `mapstructure:"DISCOVER_V2_POOLS"`
	DiscoverV3Pools         bool     `mapstructure:"DISCOVER_V3_POOLS"`
	UniswapV2Factory        string   `mapstructure:"UNISWAP_V2_FACTORY"`
	UniswapV3Factory        string   `mapstructure:"UNISWAP_V3_FACTORY"`
	V2FactorySyncStartBlock uint64   `mapstructure:"V2_FACTORY_SYNC_START_BLOCK"`
	V3FactorySyncStartBlock uint64   `mapstructure:"V3_FACTORY_SYNC_START_BLOCK"`
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

// Load is a convenience wrapper that mirrors the older API used by some
// commands. It simply calls LoadConfig and returns the result.
func Load() (Config, error) {
	return LoadConfig()
}
