package Pricing

import (
	"fraktal/mev-bot-v2/Cache"
	"math/big"
)

// CalculatePriceFromState calculates the canonical price of a pool from its state.
// The canonical price is always the price of Token0 in terms of Token1.
func CalculatePriceFromState(state *Cache.PoolState) *big.Float {
	if state.IsV3Style {
		return calculateV3PriceFromState(state)
	}
	return calculateV2PriceFromState(state)
}

// calculateV2PriceFromState calculates the price for a V2-style pool.
func calculateV2PriceFromState(state *Cache.PoolState) *big.Float {
	if state.Reserve0 == nil || state.Reserve1 == nil || state.Reserve0.Sign() == 0 {
		return big.NewFloat(0)
	}
	r0F := new(big.Float).SetInt(state.Reserve0)
	r1F := new(big.Float).SetInt(state.Reserve1)

	// Raw price of T0 in terms of T1 is reserve1 / reserve0
	rawPrice := new(big.Float).Quo(r1F, r0F)

	// Adjust for decimals to get the human-readable price.
	// price = rawPrice * 10^(dec0 - dec1)
	dec0 := new(big.Int).Exp(big.NewInt(10), big.NewInt(int64(state.Token0Decimals)), nil)
	dec1 := new(big.Int).Exp(big.NewInt(10), big.NewInt(int64(state.Token1Decimals)), nil)
	dec0F := new(big.Float).SetInt(dec0)
	dec1F := new(big.Float).SetInt(dec1)
	priceAdjustmentFactor := new(big.Float).Quo(dec0F, dec1F)

	return new(big.Float).Mul(rawPrice, priceAdjustmentFactor)
}

// calculateV3PriceFromState calculates the price for a V3-style pool.
// This is the final, correct version with the numerator and denominator fixed.
func calculateV3PriceFromState(state *Cache.PoolState) *big.Float {
	if state.SqrtPriceX96 == nil || state.SqrtPriceX96.Sign() == 0 {
		return big.NewFloat(0)
	}

	// The formula for the price of token0 in terms of token1 is:
	// P(T0/T1) = (2^192 / (sqrtPriceX96^2)) * (10^decimals0 / 10^decimals1)
	// To avoid precision loss, we perform this with big.Int math:
	// Numerator   = 2^192 * 10^decimals0
	// Denominator = sqrtPriceX96^2 * 10^decimals1

	// CORRECTED: Numerator
	two192 := new(big.Int).Exp(big.NewInt(2), big.NewInt(192), nil)
	dec0Factor := new(big.Int).Exp(big.NewInt(10), big.NewInt(int64(state.Token0Decimals)), nil)
	numerator := new(big.Int).Mul(two192, dec0Factor)

	// CORRECTED: Denominator
	sqrtPriceX96Squared := new(big.Int).Mul(state.SqrtPriceX96, state.SqrtPriceX96)
	dec1Factor := new(big.Int).Exp(big.NewInt(10), big.NewInt(int64(state.Token1Decimals)), nil)
	denominator := new(big.Int).Mul(sqrtPriceX96Squared, dec1Factor)

	if denominator.Sign() == 0 {
		return big.NewFloat(0)
	}

	// Final Price = Numerator / Denominator
	numF := new(big.Float).SetInt(numerator)
	denF := new(big.Float).SetInt(denominator)

	// Set precision to handle a wide range of price values accurately.
	numF.SetPrec(256)
	denF.SetPrec(256)

	finalPrice := new(big.Float).Quo(numF, denF)
	return finalPrice
}
