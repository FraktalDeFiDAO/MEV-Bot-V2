# **High-Frequency Arbitrage Bot (MEV)**

This repository contains the full codebase for a high-frequency arbitrage bot designed to identify and execute profitable opportunities on decentralized exchanges (DEXs) on EVM-compatible chains. The system is architected to be robust, secure, and maintainable, leveraging a Diamond Standard proxy for on-chain execution and a modular Go backend for off-chain monitoring and transaction submission.

## **System Architecture**

The system is composed of two primary parts: an **On-Chain Component** (Solidity smart contracts) and an **Off-Chain Component** (Go services).
```mermaid
graph TD  
    subgraph Off-Chain Infrastructure (Go)  
        A\[Ethereum RPC Node\] \--\> B{Subscriber};  
        B \--\> C{EventRouter};  
        C \--\>|New Pool| D\[Discovery\];  
        C \--\>|Swap Event| E\[Market\];  
        D \--\> F\[Database\];  
        E \--\> F;  
        E \--\> G\[Scanner\];  
        F \--\> G;  
        G \--\>|Profitable Opportunity| H{Dispatcher};  
        H \--\> I\[Executor\];  
    end

    subgraph On-Chain Infrastructure (Solidity)  
        J\[Diamond Proxy\]  
        J \-- delegates call to \--\> K\[ArbitrageFacet\];  
        K \-- flash loan \--\> L\[Aave Lending Pool\];  
        K \-- swap \--\> M\[Uniswap V2/V3 Pools\];  
    end

    I \-- signs & sends tx \--\> A;  
    I \-- calls executeAaveArbitrage() \--\> J;

    style J fill:\#f9f,stroke:\#333,stroke-width:2px  
    style I fill:\#bbf,stroke:\#333,stroke-width:2px
```

### **Key Components**

#### **On-Chain (Solidity)**

* **Diamond.sol**: The central proxy contract that follows the EIP-2535 Diamond Standard. It provides upgradeability and modularity by delegating calls to various facets.  
* **ArbitrageFacet.sol**: The core execution logic. It receives instructions from the off-chain bot, requests a flash loan from Aave, executes a sequence of two trades, and repays the loan within a single atomic transaction.  
* **AccessControlFacet.sol**: Manages ownership and role-based access for administrative functions on the Diamond.

#### **Off-Chain (Go)**

* **Subscriber**: Connects to an Ethereum RPC node via WebSocket and subscribes to Swap events from major DEXs.  
* **EventRouter**: Receives raw logs from the Subscriber and routes them to the appropriate service for processing.  
* **Market**: Processes Swap events, updating the local state (reserves) of liquidity pools.  
* **Scanner**: Triggered by the Market service after a state update. It analyzes pool prices to identify potential arbitrage opportunities.  
* **Dispatcher**: A simple service that receives profitable opportunities from the Scanner and passes them to the Executor.  
* **Executor**: The final stage. It receives an opportunity, builds a valid EIP-1559 transaction, signs it with the bot's private key, and submits it to the network with a resilient retry mechanism.  
* **Config**: Handles secure loading of configuration, ensuring sensitive data like private keys are loaded from environment variables, not config files.

## **Setup & Installation**

### **Prerequisites**

* [Go](https://go.dev/doc/install) (version 1.18+)
* [Foundry](https://getfoundry.sh/) for smart contract development and testing.
* Docker and Docker Compose
* An Ethereum RPC endpoint URL (e.g., from Infura or Alchemy).

### **Quickstart (Docker & Makefile)**

Run the following commands from the project root:

```bash
make setup      # Build containers and install all dependencies
make run-dev    # Build the bot and start it along with Anvil
```

Stop the containers with:

```bash
make down
```

### **1\. Smart Contracts**

Navigate to the smart-contracts directory.

**Install Dependencies:**

forge install

Run Tests:  
Ensure you have a MAINNET\_RPC\_URL variable set in your environment.  
forge test \--fork-url $MAINNET\_RPC\_URL \-vv

Deploy:  
Deployment scripts should be configured and run via Foundry's scripting capabilities.

### **2\. Backend Service**

Navigate to the bot directory.

**Install Dependencies:**

go mod tidy

**Configuration:**

1. Copy config/config.example.yaml to config/config.yaml.  
2. Update config.yaml with your non-sensitive information (e.g., your RPC URL).  
3. Set the executor's private key as an environment variable. **DO NOT** hardcode it.  
   export EXECUTOR\_PRIVATE\_KEY="your\_private\_key\_without\_0x"

**Run Tests:**

go test ./...

**Run the Bot:**

go run main.go  
