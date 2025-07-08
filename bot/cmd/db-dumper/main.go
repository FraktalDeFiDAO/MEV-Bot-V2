// cmd/db-dumper/main.go
package main

import (
	"database/sql"
	"encoding/json"
	"flag"
	"log"
	"os"

	_ "github.com/mattn/go-sqlite3"
)

// --- Data Structures to hold DB content ---

type Token struct {
	Address  string `json:"address"`
	Symbol   string `json:"symbol"`
	Decimals int    `json:"decimals"`
}

type Pool struct {
	Address       string `json:"address"`
	Protocol      string `json:"protocol"`
	Factory       string `json:"factory"` // Added Factory field
	AddressTicker string `json:"address_ticker"`
	SymbolTicker  string `json:"symbol_ticker"`
	Token0Address string `json:"token0_address"`
	Token1Address string `json:"token1_address"`
}

type V2Swap struct {
	TxHash      string  `json:"tx_hash"`
	LogIndex    int     `json:"log_index"`
	PoolAddress string  `json:"pool_address"`
	Sender      string  `json:"sender"`
	Recipient   string  `json:"recipient"`
	Amount0In   string  `json:"amount0_in"`
	Amount1In   string  `json:"amount1_in"`
	Amount0Out  string  `json:"amount0_out"`
	Amount1Out  string  `json:"amount1_out"`
	Price       float64 `json:"price"`
	Timestamp   string  `json:"timestamp"`
}

type V3Swap struct {
	TxHash      string  `json:"tx_hash"`
	LogIndex    int     `json:"log_index"`
	PoolAddress string  `json:"pool_address"`
	Sender      string  `json:"sender"`
	Recipient   string  `json:"recipient"`
	Amount0     string  `json:"amount0"`
	Amount1     string  `json:"amount1"`
	Tick        string  `json:"tick"`
	Price       float64 `json:"price"`
	Timestamp   string  `json:"timestamp"`
}

type ArbitrageOpportunity struct {
	ID            int     `json:"id"`
	SymbolTicker  string  `json:"symbol_ticker"`
	PoolAAddress  string  `json:"pool_a_address"`
	PoolAProtocol string  `json:"pool_a_protocol"`
	PoolAPrice    float64 `json:"pool_a_price"`
	PoolBAddress  string  `json:"pool_b_address"`
	PoolBProtocol string  `json:"pool_b_protocol"`
	PoolBPrice    float64 `json:"pool_b_price"`
	PercentDiff   float64 `json:"percent_diff"`
	Timestamp     string  `json:"timestamp"`
}

// FullDump contains all the data from the database.
type FullDump struct {
	Tokens                 []Token                `json:"tokens"`
	Pools                  []Pool                 `json:"pools"`
	V2Swaps                []V2Swap               `json:"v2_swaps"`
	V3Swaps                []V3Swap               `json:"v3_swaps"`
	ArbitrageOpportunities []ArbitrageOpportunity `json:"arbitrage_opportunities"`
}

func main() {
	// --- Command-Line Flags ---
	dbPath := flag.String("db", "./mev-data.db", "Path to the SQLite database file.")
	outPath := flag.String("out", "./db_dump.json", "Path for the JSON output file.")
	flag.Parse()

	log.Printf("Dumping database from '%s' to '%s'...\n", *dbPath, *outPath)

	// --- Connect to DB ---
	db, err := sql.Open("sqlite3", *dbPath)
	if err != nil {
		log.Fatalf("Failed to open database: %v", err)
	}
	defer db.Close()

	dump := FullDump{}

	// --- Query Each Table ---
	dump.Tokens, err = queryTokens(db)
	if err != nil {
		log.Fatalf("Failed to query tokens: %v", err)
	}

	dump.Pools, err = queryPools(db)
	if err != nil {
		log.Fatalf("Failed to query pools: %v", err)
	}

	dump.V2Swaps, err = queryV2Swaps(db)
	if err != nil {
		log.Fatalf("Failed to query V2 swaps: %v", err)
	}

	dump.V3Swaps, err = queryV3Swaps(db)
	if err != nil {
		log.Fatalf("Failed to query V3 swaps: %v", err)
	}

	dump.ArbitrageOpportunities, err = queryArbOpportunities(db)
	if err != nil {
		log.Fatalf("Failed to query arbitrage opportunities: %v", err)
	}

	// --- Marshal to JSON and Write to File ---
	jsonData, err := json.MarshalIndent(dump, "", "  ") // Pretty print
	if err != nil {
		log.Fatalf("Failed to marshal data to JSON: %v", err)
	}

	err = os.WriteFile(*outPath, jsonData, 0644)
	if err != nil {
		log.Fatalf("Failed to write JSON to file: %v", err)
	}

	log.Printf("Successfully dumped %d tokens, %d pools, %d V2 swaps, %d V3 swaps, and %d arb opportunities.",
		len(dump.Tokens), len(dump.Pools), len(dump.V2Swaps), len(dump.V3Swaps), len(dump.ArbitrageOpportunities))
}

// --- Query Functions for Each Table ---

func queryTokens(db *sql.DB) ([]Token, error) {
	rows, err := db.Query("SELECT address, symbol, decimals FROM tokens")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tokens []Token
	for rows.Next() {
		var t Token
		if err := rows.Scan(&t.Address, &t.Symbol, &t.Decimals); err != nil {
			return nil, err
		}
		tokens = append(tokens, t)
	}
	return tokens, nil
}

func queryPools(db *sql.DB) ([]Pool, error) {
	// Updated query to select the factory column
	rows, err := db.Query("SELECT address, protocol, factory, address_ticker, symbol_ticker, token0_address, token1_address FROM pools")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var pools []Pool
	for rows.Next() {
		var p Pool
		// Updated scan to include the new factory field
		if err := rows.Scan(&p.Address, &p.Protocol, &p.Factory, &p.AddressTicker, &p.SymbolTicker, &p.Token0Address, &p.Token1Address); err != nil {
			return nil, err
		}
		pools = append(pools, p)
	}
	return pools, nil
}

func queryV2Swaps(db *sql.DB) ([]V2Swap, error) {
	rows, err := db.Query("SELECT tx_hash, log_index, pool_address, sender, recipient, amount0_in, amount1_in, amount0_out, amount1_out, price, timestamp FROM v2_swaps")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var swaps []V2Swap
	for rows.Next() {
		var s V2Swap
		if err := rows.Scan(&s.TxHash, &s.LogIndex, &s.PoolAddress, &s.Sender, &s.Recipient, &s.Amount0In, &s.Amount1In, &s.Amount0Out, &s.Amount1Out, &s.Price, &s.Timestamp); err != nil {
			return nil, err
		}
		swaps = append(swaps, s)
	}
	return swaps, nil
}

func queryV3Swaps(db *sql.DB) ([]V3Swap, error) {
	rows, err := db.Query("SELECT tx_hash, log_index, pool_address, sender, recipient, amount0, amount1, tick, price, timestamp FROM v3_swaps")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var swaps []V3Swap
	for rows.Next() {
		var s V3Swap
		if err := rows.Scan(&s.TxHash, &s.LogIndex, &s.PoolAddress, &s.Sender, &s.Recipient, &s.Amount0, &s.Amount1, &s.Tick, &s.Price, &s.Timestamp); err != nil {
			return nil, err
		}
		swaps = append(swaps, s)
	}
	return swaps, nil
}

func queryArbOpportunities(db *sql.DB) ([]ArbitrageOpportunity, error) {
	rows, err := db.Query("SELECT id, symbol_ticker, pool_a_address, pool_a_protocol, pool_a_price, pool_b_address, pool_b_protocol, pool_b_price, percent_diff, timestamp FROM arbitrage_opportunities")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var opps []ArbitrageOpportunity
	for rows.Next() {
		var o ArbitrageOpportunity
		if err := rows.Scan(&o.ID, &o.SymbolTicker, &o.PoolAAddress, &o.PoolAProtocol, &o.PoolAPrice, &o.PoolBAddress, &o.PoolBProtocol, &o.PoolBPrice, &o.PercentDiff, &o.Timestamp); err != nil {
			return nil, err
		}
		opps = append(opps, o)
	}
	return opps, nil
}
