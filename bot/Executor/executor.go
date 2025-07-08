// =================================================================================
// FILE PATH: bot/Executor/executor.go
// =================================================================================
package Executor

import (
	"context"
	"crypto/ecdsa"
	"errors"
	"log"
	"math/big"
	"strings"
	"sync"
	"time"

	// CORRECTED: Import path now points to the correct location of the generated binding.
	"fraktal/mev-bot-v2/contracts/ArbitrageFacet"
	"fraktal/mev-bot-v2/model"

	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	// CORRECTED: Fixed the typo in the import path.
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
)

// Service is responsible for signing and broadcasting arbitrage transactions.
type Service struct {
	ethClient           *ethclient.Client
	privateKey          *ecdsa.PrivateKey
	arbitrageFacet      *ArbitrageFacet.ArbitrageFacet
	aaveProviderAddress common.Address
	nonceMu             sync.Mutex
	nextNonce           uint64
	nonceInited         bool
}

// NewService creates and returns a new instance of the Executor service.
func NewService(client *ethclient.Client, pk *ecdsa.PrivateKey, diamondAddress, aaveProvider common.Address) (*Service, error) {
	// CORRECTED: The package name is CamelCase, matching the generated code.
	facetInstance, err := ArbitrageFacet.NewArbitrageFacet(diamondAddress, client)
	if err != nil {
		log.Printf("ERROR: Failed to bind to ArbitrageFacet at address %s: %v", diamondAddress.Hex(), err)
		return nil, err
	}

	return &Service{
		ethClient:           client,
		privateKey:          pk,
		arbitrageFacet:      facetInstance,
		aaveProviderAddress: aaveProvider,
	}, nil
}

// Execute takes an arbitrage opportunity and submits it to the network.
func (s *Service) Execute(opportunity *model.ArbitrageData) {
	log.Printf("Attempting to execute arbitrage for opportunity: %+v", opportunity)

	tx, err := s.createDynamicTx(context.Background(), opportunity)
	if err != nil {
		log.Printf("ERROR: Failed to create dynamic transaction: %v", err)
		return
	}

	maxRetries := 3
	retryDelay := 500 * time.Millisecond

	for i := 0; i < maxRetries; i++ {
		err = s.ethClient.SendTransaction(context.Background(), tx)
		if err == nil {
			log.Printf("Successfully sent transaction with hash: %s", tx.Hash().Hex())
			return
		}

		if strings.Contains(err.Error(), "nonce too low") || strings.Contains(err.Error(), "insufficient funds") {
			log.Printf("ERROR: Unrecoverable error sending transaction: %v. Not retrying.", err)
			return
		}

		log.Printf("WARN: Failed to send transaction (attempt %d/%d): %v. Retrying in %v...", i+1, maxRetries, err, retryDelay)
		time.Sleep(retryDelay)
		retryDelay *= 2
	}

	log.Printf("ERROR: Failed to send transaction after %d attempts. Last error: %v", maxRetries, err)
}

// createDynamicTx prepares a new EIP-1559 transaction.
func (s *Service) createDynamicTx(ctx context.Context, opportunity *model.ArbitrageData) (*types.Transaction, error) {
	fromAddress, err := s.getSenderAddress()
	if err != nil {
		return nil, err
	}

	// Allocate nonce sequentially to avoid concurrent race conditions
	s.nonceMu.Lock()
	var nonce uint64
	if !s.nonceInited {
		n, err := s.ethClient.PendingNonceAt(ctx, fromAddress)
		if err != nil {
			s.nonceMu.Unlock()
			return nil, err
		}
		nonce = n
		s.nextNonce = n + 1
		s.nonceInited = true
	} else {
		nonce = s.nextNonce
		s.nextNonce++
	}
	s.nonceMu.Unlock()

	gasTipCap, err := s.ethClient.SuggestGasTipCap(ctx)
	if err != nil {
		return nil, err
	}

	latestHeader, err := s.ethClient.HeaderByNumber(ctx, nil)
	if err != nil {
		return nil, err
	}
	baseFee := latestHeader.BaseFee

	gasFeeCap := new(big.Int).Add(
		new(big.Int).Mul(baseFee, big.NewInt(2)),
		gasTipCap,
	)

	auth, err := bind.NewKeyedTransactorWithChainID(s.privateKey, opportunity.ChainID)
	if err != nil {
		return nil, err
	}
	auth.Nonce = big.NewInt(int64(nonce))
	auth.Value = big.NewInt(0)
	auth.GasLimit = uint64(800000)
	auth.GasFeeCap = gasFeeCap
	auth.GasTipCap = gasTipCap

	// The call now uses the fields from the opportunity struct directly.
	tx, err := s.arbitrageFacet.ExecuteAaveArbitrage(
		auth,
		opportunity.LoanAssetAddress,
		opportunity.FlashLoanAmount,
		opportunity.LegA,
		opportunity.LegB,
		opportunity.MinNetProfitLoanAsset,
	)
	if err != nil {
		return nil, err
	}

	return tx, nil
}

// getSenderAddress is a helper to derive the public address from the service's private key.
func (s *Service) getSenderAddress() (common.Address, error) {
	// CORRECTED: Removed the typo. It is .Public(), not ._Public().
	publicKey := s.privateKey.Public()
	publicKeyECDSA, ok := publicKey.(*ecdsa.PublicKey)
	if !ok {
		return common.Address{}, errors.New("error casting public key to ECDSA")
	}
	return bind.PubkeyToAddress(*publicKeyECDSA), nil
}
