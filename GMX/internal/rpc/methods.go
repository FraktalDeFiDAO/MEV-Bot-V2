// FILE: internal/rpc/methods.go

package rpc

import (
	"encoding/json"
	"errors"
	"math/big"
)

type OpenPositionParams struct {
	Market     string   `json:"market"`
	Leverage   float64  `json:"leverage"`
	Collateral *big.Int `json:"collateral"`
	Direction  string   `json:"direction"` // "long" or "short"
}

type ClosePositionParams struct {
	Market string `json:"market"`
	User   string `json:"user"`
}

func RegisterMethods(s *Server) {
	s.Register("OpenPosition", OpenPosition)
	s.Register("ClosePosition", ClosePosition)
	s.Register("GetPosition", GetPosition)
}

func OpenPosition(params json.RawMessage) (interface{}, error) {
	var p OpenPositionParams
	if err := json.Unmarshal(params, &p); err != nil {
		return nil, err
	}
	// TODO: Add business logic to open a position
	return map[string]interface{}{
		"status":    "opened",
		"market":    p.Market,
		"leverage":  p.Leverage,
		"direction": p.Direction,
	}, nil
}

func ClosePosition(params json.RawMessage) (interface{}, error) {
	var p ClosePositionParams
	if err := json.Unmarshal(params, &p); err != nil {
		return nil, err
	}
	// TODO: Add business logic to close a position
	return map[string]string{
		"status": "closed",
		"market": p.Market,
	}, nil
}

func GetPosition(params json.RawMessage) (interface{}, error) {
	type getParams struct {
		Market string `json:"market"`
		User   string `json:"user"`
	}
	var p getParams
	if err := json.Unmarshal(params, &p); err != nil {
		return nil, err
	}
	// TODO: Replace with real position lookup
	if p.Market == "" || p.User == "" {
		return nil, errors.New("invalid parameters")
	}
	return map[string]interface{}{
		"market":   p.Market,
		"user":     p.User,
		"size":     "1000000000000000000", // 1.0e18 dummy
		"entry":    "2000",
		"leverage": 5,
	}, nil
}
