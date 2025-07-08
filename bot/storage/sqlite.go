package storage

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"time"

	"fraktal/mev-bot-v2/uniswap"

	_ "github.com/mattn/go-sqlite3"
)

type SQLiteStore struct {
	db  *sql.DB
	dsn string
}

func NewSQLiteStore(dsn string) *SQLiteStore {
	return &SQLiteStore{dsn: dsn}
}

func (s *SQLiteStore) Connect() error {
	dbDir := filepath.Dir(s.dsn)
	if _, err := os.Stat(dbDir); os.IsNotExist(err) {
		if mkErr := os.MkdirAll(dbDir, 0755); mkErr != nil {
			return fmt.Errorf("failed to create database directory %s: %w", dbDir, mkErr)
		}
	}

	db, err := sql.Open("sqlite3", s.dsn+"?_journal_mode=WAL&_busy_timeout=5000")
	if err != nil {
		return err
	}
	s.db = db
	return s.db.Ping()
}

func (s *SQLiteStore) Close() error {
	if s.db != nil {
		return s.db.Close()
	}
	return nil
}

func (s *SQLiteStore) Migrate() error {
	query := `
    CREATE TABLE IF NOT EXISTS pool_updates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pool_address TEXT NOT NULL,
        protocol TEXT NOT NULL,
        token0_address TEXT,
        token1_address TEXT,
        token0_symbol TEXT,
        token1_symbol TEXT,
        token0_decimals INTEGER,
        token1_decimals INTEGER,
        reserve0 TEXT,          -- V2, stored as string
        reserve1 TEXT,          -- V2, stored as string
        sqrt_price_x96 TEXT,    -- V3, stored as string
        liquidity TEXT,         -- V3, stored as string
        tick TEXT,              -- V3, stored as string
        price_token0_for_token1 REAL,
        price_token1_for_token0 REAL,
        timestamp DATETIME NOT NULL -- Removed UNIQUE constraint on pool_address, timestamp for simplicity; can be added if strictness is required
    );
    CREATE INDEX IF NOT EXISTS idx_pool_address_timestamp ON pool_updates (pool_address, timestamp DESC);
    CREATE INDEX IF NOT EXISTS idx_token_addresses ON pool_updates (token0_address, token1_address);
    CREATE INDEX IF NOT EXISTS idx_protocol_pool ON pool_updates (protocol, pool_address);
    `
	_, err := s.db.Exec(query)
	return err
}

func (s *SQLiteStore) SavePoolUpdate(data *uniswap.PoolData) error {
	stmt, err := s.db.Prepare(`
        INSERT INTO pool_updates (
            pool_address, protocol, token0_address, token1_address, token0_symbol, token1_symbol, token0_decimals, token1_decimals,
            reserve0, reserve1, sqrt_price_x96, liquidity, tick,
            price_token0_for_token1, price_token1_for_token0, timestamp
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `)
	if err != nil {
		return fmt.Errorf("prepare statement: %w", err)
	}
	defer stmt.Close()

	var r0, r1, sp, l, t sql.NullString
	if data.Reserve0 != nil {
		r0.String = data.Reserve0.String()
		r0.Valid = true
	}
	if data.Reserve1 != nil {
		r1.String = data.Reserve1.String()
		r1.Valid = true
	}
	if data.SqrtPriceX96 != nil {
		sp.String = data.SqrtPriceX96.String()
		sp.Valid = true
	}
	if data.Liquidity != nil {
		l.String = data.Liquidity.String()
		l.Valid = true
	}
	if data.Tick != nil {
		t.String = data.Tick.String()
		t.Valid = true
	}

	_, err = stmt.Exec(
		strings.ToLower(data.PoolAddress), data.Protocol,
		strings.ToLower(data.Token0Address), strings.ToLower(data.Token1Address),
		data.Token0Symbol, data.Token1Symbol, data.Token0Decimals, data.Token1Decimals,
		r0, r1, sp, l, t,
		data.PriceToken0ForToken1, data.PriceToken1ForToken0, data.Timestamp.UTC(), // Ensure UTC
	)
	if err != nil {
		jsonData, _ := json.Marshal(data) // For easier debugging
		log.Printf("Error saving pool update for %s: %v. Data: %s", data.PoolAddress, err, string(jsonData))
		return fmt.Errorf("exec statement for %s: %w", data.PoolAddress, err)
	}
	return nil
}

func (s *SQLiteStore) GetLatestPoolUpdate(poolAddress string) (*uniswap.PoolData, error) {
	row := s.db.QueryRow(`
        SELECT
            pool_address, protocol, token0_address, token1_address, token0_symbol, token1_symbol, token0_decimals, token1_decimals,
            reserve0, reserve1, sqrt_price_x96, liquidity, tick,
            price_token0_for_token1, price_token1_for_token0, timestamp
        FROM pool_updates
        WHERE pool_address = ?
        ORDER BY timestamp DESC
        LIMIT 1
    `, strings.ToLower(poolAddress))

	data := &uniswap.PoolData{}
	var r0, r1, sp, l, t sql.NullString
	var ts time.Time // To scan timestamp directly

	err := row.Scan(
		&data.PoolAddress, &data.Protocol, &data.Token0Address, &data.Token1Address,
		&data.Token0Symbol, &data.Token1Symbol, &data.Token0Decimals, &data.Token1Decimals,
		&r0, &r1, &sp, &l, &t,
		&data.PriceToken0ForToken1, &data.PriceToken1ForToken0, &ts,
	)
	if err == sql.ErrNoRows {
		return nil, nil // Not found is not an error here, just means no data yet
	}
	if err != nil {
		return nil, err
	}
	data.Timestamp = ts.UTC() // Ensure UTC

	if r0.Valid && r0.String != "" {
		data.Reserve0, _ = new(big.Int).SetString(r0.String, 10)
	}
	if r1.Valid && r1.String != "" {
		data.Reserve1, _ = new(big.Int).SetString(r1.String, 10)
	}
	if sp.Valid && sp.String != "" {
		data.SqrtPriceX96, _ = new(big.Int).SetString(sp.String, 10)
	}
	if l.Valid && l.String != "" {
		data.Liquidity, _ = new(big.Int).SetString(l.String, 10)
	}
	if t.Valid && t.String != "" {
		data.Tick, _ = new(big.Int).SetString(t.String, 10)
	}

	return data, nil
}
