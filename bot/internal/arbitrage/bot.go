// FILE: internal/arbitrage/bot.go
package arbitrage

import (
	"context"
	"errors"
	"fmt"
	"math/big"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
	"go.uber.org/zap"

	"fraktal/autonet/internal/defi"
	"fraktal/autonet/internal/logging"
	"fraktal/autonet/internal/tx"
)

type ArbitrageBot struct {
	client    *ethclient.Client
	logger    *zap.Logger
	factory   defi.Factory
	signer    *tx.EthSigner
	routes    []defi.ArbitrageRoute
	sub       ethereum.Subscription
	logsCh    chan types.Log
	minProfit *big.Int
}

func NewArbitrageBot(client *ethclient.Client, signer *tx.EthSigner, factory defi.Factory) *ArbitrageBot {
	return &ArbitrageBot{
		client:    client,
		logger:    logging.New("arbitrage-bot"),
		factory:   factory,
		signer:    signer,
		logsCh:    make(chan types.Log),
		minProfit: big.NewInt(1e15), // default to 0.001 ETH
	}
}

func (bot *ArbitrageBot) LoadRoutes(routes []defi.ArbitrageRoute) {
	bot.routes = routes
}

func (bot *ArbitrageBot) SubscribeToEvents(ctx context.Context, addresses []common.Address) error {
	query := ethereum.FilterQuery{
		Addresses: addresses,
	}
	sub, err := bot.client.SubscribeFilterLogs(ctx, query, bot.logsCh)
	if err != nil {
		return fmt.Errorf("failed to subscribe to logs: %w", err)
	}
	bot.sub = sub
	return nil
}

func (bot *ArbitrageBot) Run(ctx context.Context) error {
	if len(bot.routes) == 0 {
		return errors.New("no arbitrage routes loaded")
	}

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case err := <-bot.sub.Err():
			bot.logger.Error("log subscription error", zap.Error(err))
			return err
		case ev := <-bot.logsCh:
			go bot.processEvent(ctx, ev)
		}
	}
}

func (bot *ArbitrageBot) processEvent(ctx context.Context, log types.Log) {
	for _, route := range bot.routes {
		profit, err := route.EstimateProfit(bot.client)
		if err != nil {
			bot.logger.Warn("profit estimation failed", zap.String("route", route.String()), zap.Error(err))
			continue
		}
		if profit.Cmp(bot.minProfit) <= 0 {
			continue
		}

		bot.logger.Info("profitable opportunity", zap.String("route", route.String()), zap.String("profit", profit.String()))
		txOpts, err := bind.NewKeyedTransactorWithChainID(bot.signer.PrivateKey, bot.signer.ChainID)
		if err != nil {
			bot.logger.Error("tx signer failure", zap.Error(err))
			continue
		}

		txHash, err := route.ExecuteWithFlashloan(bot.client, txOpts)
		if err != nil {
			bot.logger.Error("execution failed", zap.String("route", route.String()), zap.Error(err))
			continue
		}
		bot.logger.Info("arbitrage executed", zap.String("tx", txHash.Hex()))
	}
}
