// =================================================================
// FILE: config/config.go
// =================================================================
// This new file handles all configuration loading using viper.
package config

import (
	"log"
	"strings"

	"github.com/joho/godotenv"
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
	// --- Load .env files if present ---
	_ = godotenv.Load("../.env", ".env")

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

// Load is a backward-compatible alias for LoadConfig.
func Load() (Config, error) {
	return LoadConfig()
}
