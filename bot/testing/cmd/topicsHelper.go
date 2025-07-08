package main

import (
	"fmt"
	"log"
	"strings"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
)

// A common ABI for an ERC20 contract, focusing on the Transfer event.
// event Transfer(address indexed from, address indexed to, uint256 value);
const tokenABI = `[
    {
        "constant": true,
        "inputs": [],
        "name": "name",
        "outputs": [
            {
                "name": "",
                "type": "string"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": false,
        "inputs": [
            {
                "name": "_spender",
                "type": "address"
            },
            {
                "name": "_value",
                "type": "uint256"
            }
        ],
        "name": "approve",
        "outputs": [
            {
                "name": "",
                "type": "bool"
            }
        ],
        "payable": false,
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "anonymous": false,
        "inputs": [
            {
                "indexed": true,
                "name": "from",
                "type": "address"
            },
            {
                "indexed": true,
                "name": "to",
                "type": "address"
            },
            {
                "indexed": false,
                "name": "value",
                "type": "uint256"
            }
        ],
        "name": "Transfer",
        "type": "event"
    }
]`

func main() {
	// 1. Parse the contract ABI
	// The abi.JSON helper takes a reader, so we use strings.NewReader.
	parsedABI, err := abi.JSON(strings.NewReader(tokenABI))
	if err != nil {
		log.Fatalf("Failed to parse ABI: %v", err)
	}

	// The Topics slice is what we will build. It's used in `ethereum.FilterQuery`.
	// The outer slice represents the topic position (0 to 3).
	// The inner slice allows for 'OR' conditions (e.g., multiple possible event signatures).
	// A `nil` entry acts as a wildcard for that topic position.
	var topics [][]common.Hash

	// --- Scenario 1: Find all 'Transfer' events ---

	// The first topic (Topic 0) is always the signature of the event.
	// The `go-ethereum` ABI parser calculates this for you and stores it in the Event's `ID` field.
	transferEvent := parsedABI.Events["Transfer"]
	fmt.Printf("Event Name: %s\n", transferEvent.Name)
	fmt.Printf("Event Signature Hash (Topic 0): %s\n\n", transferEvent.ID.Hex())

	// To filter for ONLY Transfer events, Topic 0 must be the event's signature hash.
	// The subsequent topics can be nil to match any value for the indexed parameters.
	topics = [][]common.Hash{{transferEvent.ID}, nil, nil}
	fmt.Println("--- Scenario 1: Find all Transfer events ---")
	printTopics(topics)

	// --- Scenario 2: Find 'Transfer' events FROM a specific address ---

	// Let's say we want to find all transfers sent *from* this address.
	fromAddress := common.HexToAddress("0x1111111111111111111111111111111111111111")

	// The 'from' address is the first indexed parameter, so it corresponds to Topic 1.
	// To filter by an address, it must be converted to a 32-byte hash by left-padding it with zeros.
	// The common.LeftPadBytes and common.BytesToHash helpers do this.
	fromAddressTopic := common.BytesToHash(common.LeftPadBytes(fromAddress.Bytes(), 32))
	fmt.Printf("Address: %s\n", fromAddress.Hex())
	fmt.Printf("Padded Address Hash (Topic 1): %s\n\n", fromAddressTopic.Hex())

	// Topic 0: Event Signature
	// Topic 1: 'from' address
	// Topic 2: 'to' address (wildcard, so we use nil)
	topics = [][]common.Hash{{transferEvent.ID}, {fromAddressTopic}, nil}
	fmt.Println("--- Scenario 2: Find transfers FROM a specific address ---")
	printTopics(topics)

	// --- Scenario 3: Find 'Transfer' events TO a specific address ---

	toAddress := common.HexToAddress("0x2222222222222222222222222222222222222222")
	toAddressTopic := common.BytesToHash(common.LeftPadBytes(toAddress.Bytes(), 32))

	// Topic 0: Event Signature
	// Topic 1: 'from' address (wildcard, so we use nil)
	// Topic 2: 'to' address
	topics = [][]common.Hash{{transferEvent.ID}, nil, {toAddressTopic}}
	fmt.Println("--- Scenario 3: Find transfers TO a specific address ---")
	printTopics(topics)

	// --- How to build Topic 0 manually (for demonstration) ---

	// If you didn't have the ABI parser, you could compute the hash yourself.
	// This is just to show what the library does for you.
	eventSignature := []byte("Transfer(address,address,uint256)")
	eventSignatureHash := crypto.Keccak256Hash(eventSignature)
	fmt.Println("--- Manual Hash Calculation ---")
	fmt.Printf("Manual Keccak256 hash of '%s': %s\n", eventSignature, eventSignatureHash.Hex())
	fmt.Printf("Matches library's hash: %t\n", eventSignatureHash == transferEvent.ID)
}

// printTopics is a helper function to visualize the built topics slice.
func printTopics(topics [][]common.Hash) {
	fmt.Println("Generated Topics Slice:")
	for i, topicList := range topics {
		if topicList == nil {
			fmt.Printf("  Topic %d: nil (wildcard)\n", i)
			continue
		}
		for _, hash := range topicList {
			fmt.Printf("  Topic %d: %s\n", i, hash.Hex())
		}
	}
	fmt.Println("-------------------------------------------------")
}
