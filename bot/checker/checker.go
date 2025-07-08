package checker

import (
	"context"
	"fmt"
	"math/big"

	"github.com/ethereum/go-ethereum/common"
)

// QuoteResult holds the output from a single pricing query.
type QuoteResult struct {
	Protocol  string
	AmountOut *big.Int
	Error     error
}

// ExchangeChecker defines the universal interface for any DEX protocol checker.
// It abstracts the logic of getting a price quote for a given token pair.
type ExchangeChecker interface {
	// Protocol returns the name of the exchange protocol (e.g., "UniswapV2", "UniswapV3").
	Protocol() string

	// Quote gets the expected output amount for a given input amount and token pair.
	Quote(ctx context.Context, amountIn *big.Int, tokenIn, tokenOut common.Address) (*big.Int, error)
}

// MultiExchangeChecker orchestrates quoting across multiple exchange protocols.
type MultiExchangeChecker struct {
	checkers []ExchangeChecker
}

// NewMultiExchangeChecker creates a new orchestrator with a list of configured checkers.
func NewMultiExchangeChecker(checkers ...ExchangeChecker) *MultiExchangeChecker {
	return &MultiExchangeChecker{checkers: checkers}
}

// FindBestQuote concurrently queries all configured exchanges and returns the best quote.
func (mec *MultiExchangeChecker) FindBestQuote(ctx context.Context, amountIn *big.Int, tokenIn, tokenOut common.Address) (*QuoteResult, error) {
	resultsChan := make(chan *QuoteResult, len(mec.checkers))

	for _, c := range mec.checkers {
		go func(checker ExchangeChecker) {
			amountOut, err := checker.Quote(ctx, amountIn, tokenIn, tokenOut)
			resultsChan <- &QuoteResult{
				Protocol:  checker.Protocol(),
				AmountOut: amountOut,
				Error:     err,
			}
		}(c)
	}

	var bestQuote *QuoteResult

	for i := 0; i < len(mec.checkers); i++ {
		result := <-resultsChan
		if result.Error != nil {
			// Log or handle error, e.g., log.Printf("Quote failed for %s: %v", result.Protocol, result.Error)
			continue
		}

		// If this is the first successful quote or it's better than the current best, update.
		if bestQuote == nil || result.AmountOut.Cmp(bestQuote.AmountOut) > 0 {
			bestQuote = result
		}
	}

	if bestQuote == nil {
		return nil, fmt.Errorf("failed to get a quote from any exchange")
	}

	return bestQuote, nil
}
