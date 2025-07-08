### **System Prompt: Arbitrum Profit Bot (Arbitrage & Liquidations)**

**1. Core Objective**

To design, develop, and deploy a high-performance bot that autonomously identifies and executes profitable arbitrage and liquidation opportunities on the Arbitrum Layer-2 network. The system will consist of an off-chain monitoring and transaction-building component written in Golang (Go) 1.24 and an on-chain execution component written in Solidity 0.8.28.

**2. Technical Stack**

*   **Backend Language:** Golang 1.24
*   **Smart Contract Language:** Solidity 0.8.28
*   **Target Blockchain:** Arbitrum
*   **Key Go Libraries:** Go-Ethereum (Geth), go-arbitrum
*   **Smart Contract Framework:** Foundry or Hardhat

---

**3. High-Level Architecture**

The system is split into two primary components that work in tandem:

*   **Off-Chain Engine (Golang):** The "brain" of the operation. This component runs on a server, continuously monitors the Arbitrum network for opportunities, calculates profitability, and initiates transactions.
*   **On-Chain Contract (Solidity):** The "executor" of the operation. This smart contract is deployed on Arbitrum and is called by the off-chain engine. It performs the complex sequence of swaps and liquidations in a single, atomic transaction, often leveraging flash loans.

---

**4. Off-Chain Engine (Golang 1.24) Detailed Breakdown**

The Golang application is responsible for detection, calculation, and initiation. It should be built for high concurrency and low latency.

*   **4.1. Arbitrum Network Connection:**
    *   Establish a stable, low-latency connection to an Arbitrum node using a WebSocket (WS) endpoint for real-time event streaming.
    *   Use a reliable node provider (e.g., Alchemy, Infura) or a self-hosted node for maximum performance and to avoid rate-limiting.
    *   Utilize the `go-ethereum` library's `ethclient` and the `go-arbitrum` package for connectivity.

*   **4.2. Market Data Monitoring (Concurrent Goroutines):**
    *   **Arbitrage Monitoring:**
        *   Subscribe to `Sync` events from Uniswap V2-style liquidity pools and `Swap` events from Uniswap V3 pools on major Arbitrum DEXs.
        *   Monitor the mempool for pending transactions that could create price imbalances upon execution.
        *   Use goroutines to concurrently monitor multiple token pairs across various DEXs (e.g., Uniswap, Sushiswap, Curve).
    *   **Liquidation Monitoring:**
        *   Continuously query lending protocols like Aave for user accounts.
        *   For each account, fetch its health factor. A health factor below 1 indicates the account is eligible for liquidation.
        *   Prioritize monitoring large positions, as they offer the most significant liquidation bonuses.

*   **4.3. Opportunity Identification & Profitability Calculation:**
    *   **Arbitrage Logic:**
        *   Upon detecting a price change, calculate potential profits from triangular arbitrage or multi-hop swaps.
        *   The calculation must account for trading fees for each DEX protocol and potential price slippage.
    *   **Liquidation Logic:**
        *   When a liquidatable position is found, calculate the potential profit.
        *   Profit = (Value of seized collateral * Liquidation bonus) - (Cost to repay the debt).
    *   **Crucial Consideration:** The final profitability calculation for *both* strategies must subtract the estimated gas cost for the entire transaction. An opportunity is only valid if `Gross Profit > Gas Cost`.

*   **4.4. Transaction Simulation:**
    *   Before submitting any transaction to the network, perform a simulation using `eth_call` against a forked Arbitrum environment or a simulation service like Blocknative.
    *   This step is critical to verify that the transaction will succeed and be profitable, preventing losses from failed transactions where gas is still consumed.

*   **4.5. Transaction Construction and Submission:**
    *   Use the `abigen` tool to generate Go bindings from your compiled Solidity contract's ABI.
    *   Construct and sign the transaction using the bot's private key.
    *   Submit the signed transaction (`sendRawTransaction`) to the network. Implement a robust nonce management system to handle concurrent transactions.

*   **4.6. Security and Configuration:**
    *   **Private Key Management:** NEVER hardcode private keys. Use environment variables or a secure vault system.
    *   **Configuration:** Maintain a separate configuration file (e.g., YAML, JSON) for contract addresses, token addresses, RPC endpoints, and strategy parameters (e.g., minimum profit threshold).

---

**5. On-Chain Executor (Solidity 0.8.28) Detailed Breakdown**

The Solidity smart contract executes the complex trade sequences initiated by the Go bot. Its main purpose is capital efficiency and atomicity.

*   **5.1. Flash Loan Integration:**
    *   The contract must be able to programmatically borrow large amounts of capital using flash loans from a provider on Arbitrum like Aave or Balancer.
    *   This avoids the need for the bot to hold large amounts of capital, using the borrowed funds to perform the arbitrage/liquidation and repaying the loan within the same transaction.
    *   Implement the appropriate interface (e.g., Aave's `IFlashLoanSimpleReceiver`) and the required `executeOperation` callback function.

*   **5.2. Arbitrage Logic:**
    *   The contract will receive parameters from the Go bot specifying the swap path (e.g., token A -> token B on DEX 1, then token B -> token A on DEX 2).
    *   The execution flow is:
        1.  Receive flash loan (e.g., in WETH).
        2.  Approve and swap WETH for Token A on DEX 1.
        3.  Approve and swap Token A for Token B on DEX 2.
        4.  ...continue swaps as needed.
        5.  Repay the flash loan plus the provider's fee.
        6.  Transfer the remaining profit (the arbitrage gain) to the owner's wallet.

*   **5.3. Liquidation Logic:**
    *   The execution flow is:
        1.  Receive flash loan for the debt asset (e.g., USDC).
        2.  Call the `liquidationCall` function on the target lending protocol (e.g., Aave's Pool contract).
        3.  This repays the borrower's debt and transfers the discounted collateral to your contract.
        4.  Swap a portion of the received collateral back to the debt asset (USDC) to repay the flash loan and fee.
        5.  Transfer the remaining collateral (the profit) to the owner's wallet.

*   **5.4. Security and Robustness:**
    *   **Owner-only Execution:** All functions that can start a trade must be protected with an `onlyOwner` modifier to ensure only the Go bot can trigger them.
    *   **Re-entrancy Guard:** While flash loans mitigate some re-entrancy risks, apply OpenZeppelin's `ReentrancyGuard` to state-changing functions as a best practice.
    *   **Deadline/Slippage Checks:** Implement internal checks to ensure swaps do not execute if the market has moved unfavorably since the opportunity was detected.
    *   **Solidity Version:** Use `pragma solidity ^0.8.28;` to leverage built-in overflow/underflow checks.

---

**6. Target DeFi Platforms on Arbitrum**

*   **DEXs for Arbitrage:** Uniswap (V2 & V3), Sushiswap, Curve, Trader Joe, Balancer.
*   **Lending Protocols for Liquidations:** Aave, Compound, other emerging lending platforms.

---

**7. Important Considerations & Best Practices**

*   **MEV on Arbitrum:** While Arbitrum has a centralized sequencer which changes the MEV dynamics compared to Ethereum, be aware of front-running and sandwich attacks. Profitable transactions can still be seen and copied. Low-latency execution is key.
*   **Testing:** Thoroughly test the entire system on an Arbitrum testnet (e.g., Goerli) and then with mainnet forks using Foundry or Hardhat. This allows for realistic simulations without risking real funds.
*   **Logging and Monitoring:** Implement comprehensive logging in the Golang application to track detected opportunities, executed transactions, profits, and errors. This is invaluable for debugging and performance analysis.