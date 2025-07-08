package utils

import (
	"math"
	"math/big"
)

// Q96 is 2^96 as a big.Float
var Q96 = new(big.Float).SetInt(new(big.Int).Lsh(big.NewInt(1), 96))

// CalculateV3Price calculates human-readable prices from sqrtPriceX96
// price0For1 (P0/P1): how much of token1 for 1 token0.
// price1For0 (P1/P0): how much of token0 for 1 token1.
func CalculateV3Price(sqrtPriceX96 *big.Int, dec0, dec1 uint8) (price0For1, price1For0 float64) {
	if sqrtPriceX96 == nil || sqrtPriceX96.Sign() == 0 {
		return 0, 0
	}

	// Convert sqrtPriceX96 to big.Float
	sqrtPFloat := new(big.Float).SetInt(sqrtPriceX96)

	// priceRatio = (sqrtPriceX96 / 2^96)^2
	// This priceRatio is for token1 in terms of token0 (amount of token1 per token0) before decimal adjustment
	// Or, (token0 price denominated in token1) / (token1 price denominated in token1 == 1)
	// So, price_of_token0_in_token1_units = (sqrtP/Q96)^2 * 10^(dec1-dec0) according to Uniswap whitepaper notation.
	// But it's often more intuitive to think of price = amountY / amountX.
	// sqrtPriceX96 encodes sqrt(P) where P = price of token1 in terms of token0 (y/x).
	// So P = (sqrtPriceX96 / Q96)^2 is price of token1 in token0 (how much token0 for 1 token1).

	// Let's stick to Uniswap's P = y/x interpretation for sqrtPriceX96.
	// P = (sqrtRatio)^2 = price of token1 in terms of token0 (e.g. price of USDC in terms of WETH)
	// Price of Y (token1) in terms of X (token0)
	priceYperX_raw := new(big.Float).Quo(sqrtPFloat, Q96)
	priceYperX_raw.Mul(priceYperX_raw, priceYperX_raw) // This is (Token1/Token0) in raw integer amounts

	// Adjust for decimals: priceYperX_adjusted = priceYperX_raw * (10^decimals0 / 10^decimals1)
	// This gives price of token1 in terms of token0 (e.g. how many WETH for 1 USDC)
	// So, 1 token1 = X token0
	decimalFactor := math.Pow10(int(dec0) - int(dec1))
	priceYperX_adjusted_bigfloat := new(big.Float).Mul(priceYperX_raw, new(big.Float).SetFloat64(decimalFactor))

	price1For0, _ = priceYperX_adjusted_bigfloat.Float64() // price of token1 in terms of token0

	if price1For0 == 0 {
		price0For1 = 0 // to avoid division by zero, though if price1For0 is 0, price0For1 is effectively infinite
	} else {
		price0For1 = 1.0 / price1For0 // price of token0 in terms of token1
	}

	return price0For1, price1For0
}

// CalculateV2Price calculates human-readable prices from reserves
// price0For1 (P0/P1): how much of token1 for 1 token0.
// price1For0 (P1/P0): how much of token0 for 1 token1.
func CalculateV2Price(reserve0, reserve1 *big.Int, dec0, dec1 uint8) (price0For1, price1For0 float64) {
	if reserve0 == nil || reserve1 == nil || reserve0.Sign() == 0 || reserve1.Sign() == 0 {
		return 0, 0
	}

	r0Float := new(big.Float).SetInt(reserve0)
	r1Float := new(big.Float).SetInt(reserve1)

	// Price of token0 in terms of token1 = reserve1 / reserve0 (before decimal adjustment)
	// So, 1 unit of token0 costs (reserve1/reserve0) units of token1.
	price0For1_raw := new(big.Float).Quo(r1Float, r0Float)

	// Adjust for decimals:
	// P0/P1 = (R1/10^dec1) / (R0/10^dec0) = (R1/R0) * (10^dec0 / 10^dec1)
	decimalFactor := math.Pow10(int(dec0) - int(dec1))
	price0For1_adjusted_bigfloat := new(big.Float).Mul(price0For1_raw, new(big.Float).SetFloat64(decimalFactor))

	price0For1, _ = price0For1_adjusted_bigfloat.Float64()

	if price0For1 == 0 {
		price1For0 = 0 // Or could be math.Inf(1) depending on interpretation if price0For1 is truly zero
	} else {
		price1For0 = 1.0 / price0For1
	}
	return price0For1, price1For0
}
