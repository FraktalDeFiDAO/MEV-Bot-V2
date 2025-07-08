// =================================================================================
// FILE PATH: bot/model/opportunity.go
// =================================================================================
package model

import (
	// CORRECTED: The import path now points to the correct location of the
	// generated binding, based on your project's structure.
	"fraktal/mev-bot-v2/contracts/ArbitrageFacet"
	"math/big"

	"github.com/ethereum/go-ethereum/common"
)

// ArbitrageData defines the structure for a detected arbitrage opportunity.
// It is used to pass opportunity details from the Scanner to the Executor.
type ArbitrageData struct {
	// CORRECTED: These types now correctly reference the generated binding package.
	LegA                  ArbitrageFacet.ActionSwapParams
	LegB                  ArbitrageFacet.ActionSwapParams
	FlashLoanAmount       *big.Int
	LoanAssetAddress      common.Address
	MinNetProfitLoanAsset *big.Int
	ChainID               *big.Int
	// The following fields are for logging/dispatching, not on-chain execution.
	SymbolTicker string
	PercentDiff  float64
}
