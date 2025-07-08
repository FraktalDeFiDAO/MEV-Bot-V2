# Codebase Documentation

This document provides a comprehensive overview of the MEV (Maximal Extractable Value) bot codebase, including its smart contracts, off-chain Go services, and development environment configuration.

---

## High-Level Architecture

The system is a sophisticated MEV bot designed to detect and execute arbitrage opportunities on DEXs. It consists of two main components:

1.  **On-Chain Smart Contracts (`smart-contracts/`)**: A modular and upgradable smart contract system built using the **EIP-2535 Diamond Standard**. This diamond contract is the single entry point for all on-chain operations. Different "facets" (contracts) are attached to the diamond to handle specific functionalities like access control, arbitrage execution, and managing registries for tokens and exchanges. The core arbitrage logic is centered around receiving a flash loan from a protocol like Aave, performing a series of swaps across different liquidity pools, and repaying the loan with a profit in a single atomic transaction.

2.  **Off-Chain Go Bot (`bot/`)**: A Go application that performs the heavy lifting of market analysis. It runs in two distinct modes:
    * **Dispatcher Mode**: This mode is responsible for scanning the blockchain. It subscribes to new blocks and swap events, discovers new liquidity pools, parses event data, calculates prices, caches market states, and constantly scans for price discrepancies between pools that represent an arbitrage opportunity. When an opportunity is found, it broadcasts the details over a WebSocket connection.
    * **Executor Mode**: This mode connects to the Dispatcher's WebSocket. It listens for broadcasted opportunities and, upon receiving one, constructs and submits the arbitrage transaction to the on-chain Diamond contract, using a private key to sign it.

The entire system is designed to be run in a containerized environment using Docker, with an `anvil` instance forking a live network (like Arbitrum) for realistic testing and development.

---

## Development & Build Environment

These files define how the project is built, run, and tested in a local environment.

### 📜 `docker-compose.yml`

This file orchestrates the local development environment using Docker, defining three main services that work together.

* **`anvil` service**:
    * **Intent**: To provide a local, high-performance blockchain for testing and development.
    * **Mechanics**: It uses a Foundry `anvil` image. The key feature is that it's configured to **fork** the Arbitrum mainnet from a specific block number (`--fork-url ${ARBITRUM_MAINNET_RPC_URL}` and `--fork-block-number ${FORK_BLOCK_NUMBER}`). This creates a realistic replica of the live chain state at that block, allowing for accurate testing of arbitrage logic without spending real gas. It exposes the standard RPC port `8545`.

* **`mev-bot-v2` service**:
    * **Intent**: To run the Go application (the off-chain bot).
    * **Mechanics**: It uses a standard `golang` image and mounts the local `bot/` directory into the container. Crucially, its `RPC_URL` environment variable is hardcoded to `http://anvil:8545`, ensuring that the bot connects to the local forked `anvil` service instead of a public RPC endpoint. This allows the bot to scan and interact with the forked chain state.

* **`smart-contracts-dev` service**:
    * **Intent**: To provide an environment for compiling, deploying, and interacting with the Solidity smart contracts.
    * **Mechanics**: It uses a Foundry image and mounts the `smart-contracts/` directory. Like the bot, its `RPC_URL` is set to point to the `anvil` service, so `forge` scripts (like deployment and upgrades) can be run from within this container against the local forked chain.

---

### 📜 `generate_bindings.sh`

This is a utility script to automate the creation of Go bindings for the Solidity smart contracts.

* **Intent**: To bridge the gap between the on-chain Solidity code and the off-chain Go code. Running this script creates Go packages that allow the Go application to interact with the deployed smart contracts in a type-safe way (i.e., calling functions, unpacking events).

* **Mechanics**:
    1.  It first runs `forge build --via-ir` to ensure all smart contract artifacts (`.json` files containing ABI and bytecode) are up-to-date. The `--via-ir` flag is used for optimization and may be required for complex contracts.
    2.  It defines a list of contracts (`CONTRACTS`) for which bindings should be generated.
    3.  It iterates through this list, finding the corresponding JSON artifact in the `smart-contracts/out/` directory.
    4.  It uses the `abigen` tool (part of `go-ethereum`) to generate a Go file for each contract. It extracts the ABI and bytecode from the JSON artifact and passes them to `abigen`.
    5.  The generated Go files are placed in the `bot/contracts/bindings/` directory, organized into sub-packages named after each contract.

---

## Smart Contracts (`smart-contracts/`)

The on-chain component is architected as an EIP-2535 Diamond, providing modularity and upgradability.

### Core Diamond Contracts

These contracts form the foundation of the EIP-2535 Diamond implementation.

#### `src/Diamond.sol` 

* **Intent**: This is the main entry point of the diamond proxy contract. It owns the state and delegates all external function calls to the appropriate facet.
* **`constructor`**: Initializes the diamond by setting the contract owner and performing the initial `diamondCut`. The cut adds the initial set of facets and their functions and can execute an initialization function. 
* **`fallback()`**: This is the heart of the diamond pattern. When a function is called on the diamond, this fallback is triggered. It looks up the function signature (`msg.sig`) in its storage to find the correct facet address. It then uses `delegatecall` to pass the execution to that facet, effectively running the facet's code in the context of the diamond's storage. This allows the diamond to have more functions than a single contract can hold and to add/remove/replace them over time. 
* **`receive()`**: A standard empty `receive` function to allow the contract to accept native Ether.

#### `src/libraries/LibDiamond.sol` 

* **Intent**: A stateful library that contains all the core logic for managing the diamond's structure, including its ownership and the `diamondCut` process. It directly manipulates the diamond's storage.
* **`diamondStorage()`**: Defines the `DiamondStorage` struct, which holds the critical mappings from function selectors to facet addresses, the list of all selectors, supported interface IDs, and the contract owner. It uses a specific storage slot (`DIAMOND_STORAGE_POSITION`) to prevent storage collisions with other libraries or facets. 
* **`setContractOwner()` / `contractOwner()` / `enforceIsContractOwner()`**: Standard ownership management functions. 
* **`diamondCut()`**: This is the central function for modifying the diamond. It iterates through an array of `FacetCut` structs. Based on the `action` specified for each cut (`Add`, `Replace`, `Remove`), it calls the corresponding internal helper function to modify the `facetAddressAndSelectorPosition` mapping. After processing all cuts, it can execute an optional initialization `delegatecall`. 
* **`addFunctions()`**: Adds new functions to the diamond. It ensures a function doesn't already exist before adding it to the selector-to-facet mapping. 
* **`replaceFunctions()`**: Replaces existing functions. It updates the mapping for a given selector to point to a new facet address. It includes safety checks to prevent replacing immutable functions or functions that don't exist. 
* **`removeFunctions()`**: Removes functions from the diamond by deleting their entries from the mapping and cleaning up the `selectors` array. 

#### `src/facets/DiamondCutFacet.sol` 

* **Intent**: To provide a secure, external entry point for modifying the diamond structure.
* **Mechanics**: This facet exposes a single external function, `diamondCut`. It acts as a wrapper around `LibDiamond.diamondCut`, but adds a crucial access control check: `LibDiamond.enforceIsContractOwner()`. This ensures that only the owner of the diamond can add, replace, or remove functions. 

#### `src/facets/DiamondLoupeFacet.sol` 

* **Intent**: To provide standardized "loupe" functions for external clients and tools to inspect the diamond's facets and functions, as required by the EIP-2535 standard. A "loupe" is a jeweler's magnifying glass, used here metaphorically to examine the "diamond".
* **Mechanics**: This facet implements the `IDiamondLoupe` interface.
    * **`facets()`**: Returns an array of all facets currently attached to the diamond, along with all function selectors for each facet. 
    * **`facetFunctionSelectors()`**: Returns the function selectors for a single, specified facet address. 
    * **`facetAddresses()`**: Returns a list of all unique facet addresses used by the diamond. 
    * **`facetAddress()`**: Given a function selector, returns the address of the facet that executes it. 
    * **`supportsInterface()`**: Implements the ERC-165 standard for interface detection. 

### Access Control System

This system manages ownership and role-based permissions for various administrative functions across the facets. It uses a global storage slot, meaning all facets share the same access control state.

#### `src/facets/AccessControl/IAccessControl.sol` 

* **Intent**: Defines the interface, structs, events, and errors for a role-based access control system, similar to OpenZeppelin's `AccessControl`.
* **`AccessStorage` & `RoleData`**: Defines the storage layout for owners, roles, and their members. 
* **`DEFAULT_ADMIN_ROLE`**: A special role (`bytes32(0)`) that can manage other roles. 
* **Interface Functions**: Declares standard functions like `hasRole`, `grantRole`, `revokeRole`, `owner`, `transferOwnership`, etc. 

#### `src/facets/AccessControl/LibAccessControl.sol` 

* **Intent**: This is the core logic library for the access control system. It uses its own dedicated storage slot (`keccak256("access.control.storage.v2")`) to manage all roles and ownership globally for the diamond.
* **Mechanics**:
    * **Storage Management**: Uses `accessStorage()` to get a pointer to its unique storage slot. 
    * **Enforcement Functions**: Provides internal view functions like `enforceOwner()` and `enforceRole()` that revert if the caller does not have the required permissions. These are the primary security gates used by other facets. 
    * **Role Management**: Contains the logic for `grantRole`, `revokeRole`, and `setRoleAdmin`. 
    * **Ownership Transfer**: Implements a secure two-step ownership transfer (`transferOwnership` and `acceptOwnership`) to prevent accidental loss of ownership. 
    * **`initializeOwner()`**: A critical idempotent initializer function. On its first call, it sets the contract's global owner and grants them the `DEFAULT_ADMIN_ROLE`. On subsequent calls, it does nothing, ensuring the owner can only be set once. 

#### `src/facets/AccessControl/AccessControlFacet.sol` 

* **Intent**: To provide the external EIP-2535 interface for the global access control system.
* **Mechanics**: This facet is stateless. Every function is a simple, direct wrapper around a corresponding function in `LibAccessControl`. For example, calling `AccessControlFacet.grantRole()` simply calls `LibAccessControl.grantRole()`. The access control checks (e.g., `enforceRole`) are handled within the library functions themselves. 

### Arbitrage System

This is the core business logic of the bot, handling the on-chain execution of arbitrage trades.

#### `src/facets/Arbitrage/ArbitrageFacet.sol` 

* **Intent**: This facet contains the primary logic for executing an Aave flash-loan-based arbitrage strategy.
* **`initialize()`**: An admin-only function to set up the facet with necessary addresses like WETH, the Aave Pool Provider, and an initial admin for arbitrage-specific functions. 
* **`executeAaveArbitrage()`**: This is the external function that the `Executor` bot calls to initiate an arbitrage. It takes the loan details and two `ActionSwapParams` structs, which define the two swaps (legs) of the arbitrage (e.g., Leg A: WETH -> USDC, Leg B: USDC -> WETH). It validates the swap path and then calls Aave's `flashLoan` function, passing the encoded swap parameters to the `executeOperation` callback. 
* **`executeOperation()`**: This is the Aave flash loan callback function. This is where the core atomic logic resides.
    1.  **Security Check**: It first ensures the caller is the Aave Pool. 
    2.  **Loan Received**: It receives the flash-loaned asset (e.g., WETH).
    3.  **Execute Leg A**: It calls `LibExchangeActions.swap()` to perform the first trade (e.g., swap WETH for USDC). 
    4.  **Execute Leg B**: It uses the output of Leg A as input to call `LibExchangeActions.swap()` for the second trade (e.g., swap USDC back to WETH). 
    5.  **Profit Check & Repay**: It calculates the total amount to repay (loan + Aave's premium). It checks if the final amount of the loan asset is greater than the repayment amount plus a specified minimum profit. If not, it reverts the entire transaction. 
    6.  **Repay Loan**: If profitable, it approves the Aave Pool to pull the repayment amount and returns `true`, signaling a successful flash loan. The remaining profit is kept in the contract. 
* **`withdrawTokens()`**: An admin-only function to withdraw accumulated profits from the contract. 

#### `src/libraries/LibAppStorage.sol` 

* **Intent**: Defines a shared storage space for the `ArbitrageFacet` and potentially other application-level facets.
* **`AppStorage`**: A struct that holds application-wide variables like the WETH address, the Aave Pool Provider interface, and a mapping to track profits (`profitTracker`). It uses a unique storage slot to avoid collisions. 

#### `src/facets/ExchangeHelper/LibExchangeActions.sol` 

* **Intent**: This library is the universal adapter for performing swaps across different DEX platforms (Uniswap V2/V3, Curve, Balancer). It abstracts the complexity of interacting with various router interfaces.
* **`ActionSwapParams`**: A struct that standardizes all the information needed to perform any swap, regardless of the DEX. 
* **`swap()`**: The main entry point. This function acts as a dispatcher. It first handles input funds (e.g., wrapping native ETH to WETH if needed). It then identifies the exchange platform from the `exchangeId` and delegates the actual swap logic to a platform-specific internal function (`_swapUniswapV2`, `_swapUniswapV3`, etc.). This pattern prevents the "Stack Too Deep" error that can occur in complex functions. 
* **`_swapUniswapV2()`, `_swapUniswapV3()`, etc.**: These are the specialized internal functions. Each one knows how to construct the correct parameters and call the `swap` function for its specific DEX router (e.g., `IUniswapV2Router.swapExactTokensForTokens`, `IUniswapV3SwapRouter.exactInputSingle`). 
* **Helper Functions**: Includes internal helpers like `_getActionToken` (to get a token address from its ID) and `_getRouterAndApprove` (to get the correct router address from the `ContractRegistry` and approve it to spend the input token). 

### Helper Facets and Libraries

These contracts provide registry and utility services to the main arbitrage system.

#### `src/facets/ContractRegistry/`

* **Intent**: To maintain a reliable, on-chain directory of important contract addresses (like DEX routers, factories, etc.). This avoids hardcoding addresses in other contracts, making the system more modular and easier to manage.
* **`IContractRegistry.sol`**: Defines the interface, structs, and a specific admin role (`CONTRACT_REGISTRY_ADMIN_ROLE`). 
* **`LibContractRegistry.sol`**: Contains the storage and core logic for adding contracts (`addContract`), adding contract types (`addContractType`), and retrieving contract information (`getContractByAddress`, `isContractActive`). 
* **`ContractRegistryFacet.sol`**: The external, access-controlled interface for the library. All functions that modify the registry are protected by the `onlyContractRegistryAdmin` modifier. 

#### `src/facets/TokenHelper/`

* **Intent**: Similar to the Contract Registry, this system maintains an on-chain directory of token information (name, symbol, decimals). It allows the system to refer to tokens by a simple, gas-efficient `uint16` ID instead of passing full addresses.
* **`ITokenHelper.sol`**: Defines the `TokenInfo` struct, interface functions, and the `TOKEN_ADMIN_ROLE`. 
* **`LibTokenHelper.sol`**: The core logic library. `addToken` fetches token metadata (name, symbol, decimals) directly from the token contract on-chain and stores it. It provides functions to get a token's info by its ID or address. 
* **`TokenHelperFacet.sol`**: The external interface, where functions like `addToken` and `setTokenActive` are protected by the `onlyTokenAdmin` modifier. 

#### `src/facets/ExchangeHelper/`

* **Intent**: To manage information about different DEXs. It complements the `ContractRegistry` by linking a DEX's name and platform type (e.g., UniswapV2) to its router/factory contract ID in the registry.
* **`IExchangeHelper.sol`**: Defines enums for `ExchangePlatform` and `ExchangeCategory`, the `Exchange` struct, and the `EXCHANGE_HELPER_ADMIN_ROLE`. 
* **`LibExchangeHelperStorage.sol`**: Manages the storage for exchange information. 
* **`LibExchangeUtils.sol`**: A utility library with functions to detect a pool's type (`detectExchangeType`) by checking for the existence of specific functions (duck-typing) and to derive a pool address from its factory and tokens (`getPoolOrPairAddress`). 
* **`ExchangeHelperFacet.sol`**: The external, access-controlled interface for managing exchange data. 

---

## Go Application (`bot/`)

This is the off-chain brain of the operation.

### `cmd/bot-v2-alpha/main.go` 

* **Intent**: The main entry point for the bot. It parses command-line flags to determine whether to run in "dispatcher" or "executor" mode and starts the appropriate services.
* **`runDispatcher()`**:
    * Initializes all core services: `ethclient`, `Dispatcher.Hub`, `Cache`, `Database`, `Multicall`, `Discovery`, and the main `App`.
    * It creates a `discoveryQueue` channel and passes it to the `App` (write-end) and `Discovery` service (read-end).
    * It starts all services as concurrent goroutines.
    * Finally, it starts an HTTP server to handle WebSocket connections for the `Dispatcher`.
* **`runExecutor()`**:
    * Loads the configuration, ensuring the private key and diamond address are set.
    * Initializes the `Executor` service, which connects to the blockchain.
    * Initializes the `Client`, which connects to the Dispatcher's WebSocket URL.
    * Runs the client to listen for and act on opportunities.

### `App/App.go` 

* **Intent**: This is the central orchestrator of the `dispatcher` mode. It connects and manages all other services and contains the core logic for processing logs and identifying arbitrage opportunities.
* **`App` struct**: Holds instances of all other services (`ethclient`, `DBService`, `MulticallService`, `DispatcherHub`, `Cache`, etc.). It also manages a queue for pending logs from unknown pools. 
* **`NewApp()`**: Constructor that initializes the `App` struct, including instantiating the on-chain `UniswapVersionChecker` contract helper. It also calls `loadAndCacheFromDB` to prepopulate the cache with known data. 
* **`Run()`**: The main event loop. It creates a subscription to `Swap` events from both V2 and V3 pools and passes each incoming log to `handleLog`. 
* **`handleLog()`**: The primary log processing function.
    1.  It first checks if the pool that emitted the log is already known (in the cache).
    2.  If known, it calls `handleKnownPool` to process the swap. 
    3.  If unknown, it adds the log to a `pendingLogs` map and sends the pool's address to the `DiscoveryQueue` for processing by the `Discovery` service. This prevents multiple discovery attempts for the same pool if many logs arrive at once. 
* **`handleKnownPool()`**: Parses the swap event using the `Parser` service, updates the pool's reserves in the `Cache`, saves the swap to the `Database`, and recalculates the pool's price. If the price has updated, it calls `scanForArbitrage`. 
* **`scanForArbitrage()`**: This is the core arbitrage detection logic.
    1.  It retrieves all cached pools for a given token pair (e.g., all WETH/USDC pools). 
    2.  It iterates through every combination of two pools.
    3.  It compares their canonical prices to find a spread.
    4.  It calculates if the `spread` is greater than the combined trading `fees` of the two pools.
    5.  If the potential `profitMargin` is greater than a threshold, it logs the opportunity and broadcasts it via the `DispatcherHub`. 
* **`GetPoolState()`**: A crucial function that acts as a "get-or-create" for a pool's cached state. If a pool isn't in the cache, it uses the `MulticallService` to fetch its on-chain data (tokens, factory, fee), creates a new `PoolState` object, saves it to the cache and database, and returns it. 
* **`ProcessPendingLogs()`**: After the `Discovery` service has processed a new pool, this function is called to go back and process any logs that were queued up for that pool while it was being discovered. 

### Service Packages

#### `Cache/cache.go` 

* **Intent**: Provides a thread-safe, in-memory cache for market data.
* **`Service` struct**: The main cache object. It uses two maps for efficient lookups: `TickerToPools` (maps a token pair like `weth_usdc` to a list of all pools for that pair) and `PoolToTicker` (maps a specific pool address back to its pair ticker). A `sync.RWMutex` ensures safe concurrent access from different goroutines. 
* **`PoolState` struct**: The core data structure for a single liquidity pool, holding its protocol, reserves/prices, tokens, and other relevant data. 

#### `Database/database.go` 

* **Intent**: Manages the persistent storage of data using a SQLite database. This ensures that when the bot restarts, it can quickly load its known state without having to re-discover everything from scratch.
* **`DBService` struct**: A wrapper around the `sql.DB` connection.
* **Schema**: The `CREATE TABLE` statements define the database schema for storing `tokens`, `pools`, `v2_swaps`, `v3_swaps`, and `arbitrage_opportunities`.
* **Functions**: Provides methods to `SaveToken`, `SavePool`, `SaveV2Swap`, `SaveV3Swap`, and `LoadInitialData`.

#### `Discovery/discovery.go` 

* **Intent**: To run as a dedicated background service that processes newly found, unknown pool addresses.
* **Mechanics**: It runs a simple, single-threaded loop that reads pool addresses from a channel (`queue`). For each address, it calls the main `app.GetPoolState` function, which handles the logic of fetching the pool's data, caching it, and saving it to the database. After a pool is processed, it triggers `app.ProcessPendingLogs` to handle any swaps that occurred during the discovery process.

#### `Dispatcher/dispatcher.go` 

* **Intent**: To manage WebSocket connections and broadcast arbitrage opportunities to all connected clients (i.e., the `Executor` bots).
* **`Hub` struct**: The central component that maintains a set of active client connections. It uses channels for registering, unregistering, and broadcasting messages. 
* **`Run()`**: The main loop for the hub. It listens on its channels and safely adds/removes clients or iterates through all clients to send a message. 
* **`BroadcastOpportunity()`**: Takes an `Opportunity` struct, marshals it to JSON, and puts it on the `broadcast` channel to be sent to all clients. 
* **`ServeWs()`**: The HTTP handler that upgrades an incoming HTTP request to a WebSocket connection and registers it with the hub. 

#### `Executor/executor.go` 

* **Intent**: To provide the logic for taking a detected opportunity and executing it on the blockchain.
* **`Executor` struct**: Holds the configuration, an `ethclient` for sending transactions, a transaction signer (`bind.TransactOpts`) initialized with the executor's private key, and Go bindings for the `TokenHelperFacet` and `ArbitrageFacet`. 
* **`New()`**: The constructor that initializes the `ethclient` and sets up the `signer` with the private key and chain ID. 
* **`Execute()`**: This is the core execution function.
    1.  It receives an `Opportunity` from the `Client`.
    2.  It identifies the low-price (buy) pool and the high-price (sell) pool.
    3.  It determines which token to use for the flash loan (e.g., WETH).
    4.  It uses the `tokenHelper` binding to get the on-chain `uint16` IDs for the loan asset and the intermediate asset.
    5.  It calls `buildSwapParams` twice to construct the `ActionSwapParams` for Leg A (buy) and Leg B (sell).
    6.  It calls the `arbitrageFacet.ExecuteAaveArbitrage` function via the Go binding, submitting the transaction to the network.
    7.  It launches a goroutine (`waitForReceipt`) to check if the transaction was successful or reverted.

#### `Client/client.go` 

* **Intent**: To run in `executor` mode, connecting to the `Dispatcher`'s WebSocket and passing received opportunities to the `Executor` service.
* **Mechanics**: It establishes a WebSocket connection to the dispatcher. It runs an infinite loop, reading messages from the connection. When it receives a message, it unmarshals it into an `Opportunity` struct and passes it to `executor.Execute` in a new goroutine to avoid blocking the WebSocket read loop. It also includes logic for automatic reconnection if the connection is lost.

#### `Multicall/multicall_service.go` 

* **Intent**: To provide a service that batches multiple, independent, constant function calls into a single RPC request, significantly reducing RPC overhead and improving performance.
* **Mechanics**: It uses the `go-multicall` library.
    * **`GetTokenMetadataBatch()`**: Takes a list of token addresses and efficiently fetches the `symbol` and `decimals` for any that aren't already in its local LRU cache.
    * **`FetchV2PairData()` & `FetchV3PoolData()`**: Fetches the core, static data for a single V2 or V3 pool (tokens, factory, fee).
    * **`FetchPoolReservesBatch()`**: A key function that takes a list of pools and fetches their current reserves (for V2) or token balances (for V3) in a single batch call. The implementation is careful to handle potential failures for individual calls within the batch, ensuring that one failed pool doesn't disrupt the entire batch.

#### `Parser/Parser.go` 

* **Intent**: A simple utility package to decode raw event log data into human-readable structs.
* **Mechanics**:
    * It uses `abi.JSON` to parse the ABI strings for Uniswap V2 and V3 `Swap` events during package initialization.
    * **`ParseV2Swap()` & `ParseV3Swap()`**: These functions take a raw `types.Log` object and the token decimals. They use the pre-parsed ABI to `Unpack` the event data into a struct (`LogSwapV2` or `LogSwapV3`).
    * **Price Calculation**: Crucially, after unpacking, they perform the correct decimal-adjusted price calculation. For V3, this involves squaring the `sqrtPriceX96` and adjusting for decimals. For V2, it's based on the ratio of reserves, also adjusted for decimals.

#### `Subscriber/Subscriber.go` 

* **Intent**: To provide a standardized way to subscribe to blockchain logs.
* **Mechanics**: The `Subscription` function is a simple wrapper around `ethclient.SubscribeFilterLogs`. It constructs a `ethereum.FilterQuery`, setting the `Topics` field. By allowing a slice of hashes in `Topics[0]`, it can listen for multiple event types (e.g., V2 Swaps OR V3 Swaps) in a single subscription.

#### `Updater/updater.go` 

* **Intent**: To run as a background service that periodically refreshes the reserves/prices of all known pools. This is necessary because the bot can't rely solely on `Swap` events; prices can change due to liquidity additions/removals.
* **Mechanics**: It uses a `time.Ticker` to trigger an update at a regular `interval`. The `updateAllPoolReserves` function gathers all known pools from the `Cache`, uses the `MulticallService.FetchPoolReservesBatch` to get their latest state in one call, and then updates the `Cache` with the new reserve data.

---

### Utility Packages

#### `finder/`

* **Intent**: A command-line utility to find files matching specific patterns, similar to the `find` command on Linux. It's used to bundle all Solidity source code into a single file for analysis.
* **`finder.go`**: Contains the core logic. `Run` uses `filepath.WalkDir` to recursively traverse directories. It applies include and exclude glob patterns to filter files and directories. `processFile` reads the content of matched files and writes it to the specified output, wrapped in header and footer comments.
* **`cmd/finder/main.go`**: The command-line interface for the finder utility. It uses Go's `flag` package to parse arguments for the search directory, include pattern, exclude patterns, and output file.

#### `config/config.go` 

* **Intent**: To load and manage all configuration for the application from environment variables or a `.env` file.
* **Mechanics**: It uses the `godotenv` library to load a `.env` file. The `Config` struct defines all possible configuration parameters. The `Load()` function reads each variable using helper functions (`getEnv`, `getEnvBool`, etc.) that provide sane default values if the environment variable is not set.

#### `utils/`

* **`logging.go`**: A simple package to initialize a standard logging format.
* **`math.go`**: Contains the core price calculation logic (`CalculateV3Price`, `CalculateV2Price`) used by the `Parser`. This isolates the complex mathematical conversions from the rest of the application logic.

#### `uniswap/`

* **Intent**: To centralize common definitions and event-parsing logic related to Uniswap protocols.
* **`common.go`**: Defines shared types like `ProtocolVersion` ("UniswapV2", "UniswapV3"), `PoolData` (the canonical struct for pool state), and `NewPoolNotification`.
* **`v2.go` & `v3.go`**: These files contain the ABI definitions and parsing functions (`ParseV2Sync`, `ParseV3PoolCreated`, etc.) specific to each Uniswap version. This separation keeps the protocol-specific details organized.

---
## Conclusion
