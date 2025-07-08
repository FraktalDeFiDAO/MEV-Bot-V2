package Database

import (
	"database/sql"
	"fmt"
	"fraktal/mev-bot-v2/Parser"
	"log"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum/common"
	_ "github.com/mattn/go-sqlite3"
)

// Constants to define the type of write operation.
type WriteRequestType int

const (
	SaveTokenRequest WriteRequestType = iota
	SavePoolRequest
	SaveV2SwapRequest
	SaveV3SwapRequest
	SaveOpportunityRequest
)

// DBWriteRequest is a struct that encapsulates all possible data to be written to the DB.
// This allows us to send different types of write operations over a single channel.
type DBWriteRequest struct {
	Type        WriteRequestType
	Token       *TokenRecord
	Pool        *PoolRecord
	V2Swap      *V2SwapRecord
	V3Swap      *V3SwapRecord
	Opportunity *Opportunity
}

// V2SwapRecord holds the data for a V2 swap to be written to the DB.
type V2SwapRecord struct {
	TxHash      common.Hash
	LogIndex    uint
	PoolAddress common.Address
	Swap        *Parser.LogSwapV2
}

// V3SwapRecord holds the data for a V3 swap to be written to the DB.
type V3SwapRecord struct {
	TxHash      common.Hash
	LogIndex    uint
	PoolAddress common.Address
	Swap        *Parser.LogSwapV3
}

// DBWriter manages a single database connection and a queue for write operations.
type DBWriter struct {
	db          *sql.DB
	WriteQueue  chan *DBWriteRequest
	dbPath      string
	batch       []*DBWriteRequest
	batchTicker *time.Ticker
}

// NewDBWriter creates a new DBWriter service.
func NewDBWriter(dbPath string) (*DBWriter, error) {
	db, err := sql.Open("sqlite3", dbPath+"?_journal_mode=WAL&_busy_timeout=5000")
	if err != nil {
		return nil, err
	}

	writer := &DBWriter{
		db:          db,
		WriteQueue:  make(chan *DBWriteRequest, 2048), // Buffer to handle high throughput
		dbPath:      dbPath,
		batch:       make([]*DBWriteRequest, 0, 100),
		batchTicker: time.NewTicker(2 * time.Second), // Commit batch every 2 seconds
	}

	if err := writer.migrate(); err != nil {
		return nil, fmt.Errorf("database migration failed: %w", err)
	}

	return writer, nil
}

// Run starts the DBWriter's main loop, listening for write requests on its channel.
func (w *DBWriter) Run() {
	log.Println("Database Writer service running...")
	for {
		select {
		case req := <-w.WriteQueue:
			w.batch = append(w.batch, req)
			if len(w.batch) >= 100 { // Commit if batch size is reached
				w.commitBatch()
			}
		case <-w.batchTicker.C:
			if len(w.batch) > 0 { // Commit on a timer
				w.commitBatch()
			}
		}
	}
}

// commitBatch processes the current batch of write requests in a single DB transaction.
func (w *DBWriter) commitBatch() {
	tx, err := w.db.Begin()
	if err != nil {
		log.Printf("DB Writer: Error starting transaction: %v", err)
		return
	}

	for _, req := range w.batch {
		var wErr error
		switch req.Type {
		case SaveTokenRequest:
			wErr = w.saveToken(tx, req.Token)
		case SavePoolRequest:
			wErr = w.savePool(tx, req.Pool)
		case SaveV2SwapRequest:
			wErr = w.saveV2Swap(tx, req.V2Swap)
		case SaveV3SwapRequest:
			wErr = w.saveV3Swap(tx, req.V3Swap)
		case SaveOpportunityRequest:
			wErr = w.saveArbitrageOpportunity(tx, req.Opportunity)
		}
		if wErr != nil {
			log.Printf("DB Writer: Rolling back transaction due to error: %v", wErr)
			if rbErr := tx.Rollback(); rbErr != nil {
				log.Printf("DB Writer: Error during rollback: %v", rbErr)
			}
			w.batch = w.batch[:0]
			return
		}
	}

	if err := tx.Commit(); err != nil {
		log.Printf("DB Writer: Error committing transaction: %v", err)
		if rbErr := tx.Rollback(); rbErr != nil {
			log.Printf("DB Writer: Error during rollback: %v", rbErr)
		}
	}
	w.batch = w.batch[:0] // Clear the batch
}

// migrate creates the database schema if it doesn't exist.
func (w *DBWriter) migrate() error {
	// SQL schema remains the same as before.
	createTablesSQL := `
	CREATE TABLE IF NOT EXISTS tokens (
		address TEXT PRIMARY KEY,
		symbol TEXT,
		decimals INTEGER
	);
	CREATE TABLE IF NOT EXISTS pools (
		address TEXT PRIMARY KEY,
		protocol TEXT,
		factory TEXT,
		fee REAL,
		address_ticker TEXT,
		symbol_ticker TEXT,
		token0_address TEXT,
		token1_address TEXT,
		FOREIGN KEY(token0_address) REFERENCES tokens(address),
		FOREIGN KEY(token1_address) REFERENCES tokens(address)
	);
	CREATE TABLE IF NOT EXISTS v2_swaps (
		tx_hash TEXT,
		log_index INTEGER,
		pool_address TEXT,
		sender TEXT,
		recipient TEXT,
		amount0_in TEXT,
		amount1_in TEXT,
		amount0_out TEXT,
		amount1_out TEXT,
		timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
		PRIMARY KEY (tx_hash, log_index)
	);
	CREATE TABLE IF NOT EXISTS v3_swaps (
		tx_hash TEXT,
		log_index INTEGER,
		pool_address TEXT,
		sender TEXT,
		recipient TEXT,
		amount0 TEXT,
		amount1 TEXT,
		tick TEXT,
		timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
		PRIMARY KEY (tx_hash, log_index)
	);
	CREATE TABLE IF NOT EXISTS arbitrage_opportunities (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		symbol_ticker TEXT,
		pool_a_address TEXT,
		pool_a_protocol TEXT,
		pool_a_factory TEXT,
		pool_a_price REAL,
		pool_a_fee REAL,
		pool_b_address TEXT,
		pool_b_protocol TEXT,
		pool_b_factory TEXT,
		pool_b_price REAL,
		pool_b_fee REAL,
		percent_diff REAL,
		token0_address TEXT,
		token1_address TEXT,
		token0_symbol TEXT,
		token1_symbol TEXT,
		timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
	);
	`
	_, err := w.db.Exec(createTablesSQL)
	return err
}

// LoadInitialData still reads directly as it's a one-off operation at startup.
func (w *DBWriter) LoadInitialData() ([]PoolRecord, []TokenRecord, error) {
	// ... (This function remains unchanged from the previous version)
	rowsPools, err := w.db.Query("SELECT address, protocol, factory, fee, address_ticker, symbol_ticker, token0_address, token1_address FROM pools")
	if err != nil {
		return nil, nil, err
	}
	defer rowsPools.Close()
	var pools []PoolRecord
	for rowsPools.Next() {
		var p PoolRecord
		if err := rowsPools.Scan(&p.Address, &p.Protocol, &p.Factory, &p.Fee, &p.AddressTicker, &p.SymbolTicker, &p.Token0Address, &p.Token1Address); err != nil {
			return nil, nil, err
		}
		pools = append(pools, p)
	}

	rowsTokens, err := w.db.Query("SELECT address, symbol, decimals FROM tokens")
	if err != nil {
		return nil, nil, err
	}
	defer rowsTokens.Close()
	var tokens []TokenRecord
	for rowsTokens.Next() {
		var t TokenRecord
		if err := rowsTokens.Scan(&t.Address, &t.Symbol, &t.Decimals); err != nil {
			return nil, nil, err
		}
		tokens = append(tokens, t)
	}

	return pools, tokens, nil
}

// saveToken, savePool, etc., now operate on a transaction.
func (w *DBWriter) saveToken(tx *sql.Tx, token *TokenRecord) error {
	stmt := `INSERT OR IGNORE INTO tokens (address, symbol, decimals) VALUES (?, ?, ?)`
	_, err := tx.Exec(stmt, strings.ToLower(token.Address), token.Symbol, token.Decimals)
	if err != nil {
		return fmt.Errorf("error saving token %s: %w", token.Address, err)
	}
	return nil
}

func (w *DBWriter) savePool(tx *sql.Tx, pool *PoolRecord) error {
	stmt := `INSERT OR IGNORE INTO pools (address, protocol, factory, fee, address_ticker, symbol_ticker, token0_address, token1_address) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
	_, err := tx.Exec(stmt, strings.ToLower(pool.Address), pool.Protocol, pool.Factory, pool.Fee, pool.AddressTicker, pool.SymbolTicker, strings.ToLower(pool.Token0Address), strings.ToLower(pool.Token1Address))
	if err != nil {
		return fmt.Errorf("error saving pool %s: %w", pool.Address, err)
	}
	return nil
}

func (w *DBWriter) saveV2Swap(tx *sql.Tx, record *V2SwapRecord) error {
	stmt := `INSERT OR IGNORE INTO v2_swaps (tx_hash, log_index, pool_address, sender, recipient, amount0_in, amount1_in, amount0_out, amount1_out) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
	_, err := tx.Exec(stmt, record.TxHash.Hex(), record.LogIndex, record.PoolAddress.Hex(), record.Swap.Sender.Hex(), record.Swap.To.Hex(), record.Swap.Amount0In.String(), record.Swap.Amount1In.String(), record.Swap.Amount0Out.String(), record.Swap.Amount1Out.String())
	if err != nil {
		return fmt.Errorf("error saving V2 swap for tx %s: %w", record.TxHash.Hex(), err)
	}
	return nil
}

func (w *DBWriter) saveV3Swap(tx *sql.Tx, record *V3SwapRecord) error {
	stmt := `INSERT OR IGNORE INTO v3_swaps (tx_hash, log_index, pool_address, sender, recipient, amount0, amount1, tick) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
	_, err := tx.Exec(stmt, record.TxHash.Hex(), record.LogIndex, record.PoolAddress.Hex(), record.Swap.Sender.Hex(), record.Swap.Recipient.Hex(), record.Swap.Amount0.String(), record.Swap.Amount1.String(), record.Swap.Tick.String())
	if err != nil {
		return fmt.Errorf("error saving V3 swap for tx %s: %w", record.TxHash.Hex(), err)
	}
	return nil
}

func (w *DBWriter) saveArbitrageOpportunity(tx *sql.Tx, op *Opportunity) error {
	stmt := `INSERT INTO arbitrage_opportunities (symbol_ticker, pool_a_address, pool_a_protocol, pool_a_factory, pool_a_price, pool_a_fee, pool_b_address, pool_b_protocol, pool_b_factory, pool_b_price, pool_b_fee, percent_diff, token0_address, token1_address, token0_symbol, token1_symbol) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
	_, err := tx.Exec(stmt, op.SymbolTicker, op.PoolA.Address, op.PoolA.Protocol, op.PoolA.Factory, op.PoolA.Price, op.PoolA.Fee, op.PoolB.Address, op.PoolB.Protocol, op.PoolB.Factory, op.PoolB.Price, op.PoolB.Fee, op.PercentDiff, op.Token0Address, op.Token1Address, op.Token0Symbol, op.Token1Symbol)
	if err != nil {
		return fmt.Errorf("error saving arbitrage opportunity for ticker %s: %w", op.SymbolTicker, err)
	}
	return nil
}

// Structs for DB records, kept internal to the package.
type PoolRecord struct {
	Address       string
	Protocol      string
	Factory       string
	Fee           float64
	AddressTicker string
	SymbolTicker  string
	Token0Address string
	Token1Address string
}

type TokenRecord struct {
	Address  string
	Symbol   string
	Decimals uint8
}

type Opportunity struct {
	Type          string   `json:"type"`
	SymbolTicker  string   `json:"symbol_ticker"`
	PercentDiff   float64  `json:"percent_diff"`
	Token0Address string   `json:"token0_address"`
	Token1Address string   `json:"token1_address"`
	Token0Symbol  string   `json:"token0_symbol"`
	Token1Symbol  string   `json:"token1_symbol"`
	PoolA         PoolData `json:"pool_a"`
	PoolB         PoolData `json:"pool_b"`
}

type PoolData struct {
	Address  string  `json:"address"`
	Protocol string  `json:"protocol"`
	Factory  string  `json:"factory"`
	Price    float64 `json:"price"`
	Fee      float64 `json:"fee"`
}
