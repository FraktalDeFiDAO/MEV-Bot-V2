# GMXBot: Client-Server Trading System Architecture

## Overview

This document outlines the architecture and module plan for a client-server Go-based trading bot interacting with GMX Synthetics. The system supports:

* CLI and TUI clients
* RPC and WebSocket interfaces for frontend integration
* Fully automated trade execution mode

---

## System Architecture

### 🧠 Core Components

```
                        +-------------------+
                        |   Frontend (Web)  |
                        | React/Vue + WS/RPC|
                        +---------+---------+
                                  |
                                  v
+------------------+     WebSocket+JSON-RPC     +------------------+
|     CLI Client   | <-----------------------> |     Bot Server   |
| (Manual/Scripted)|                         |  (Strategy + API) |
+--------+---------+                         +---+------------+---+
         |                                             |
         |                                             |
         |                        +----------------+   |
         +----------------------> | TUI Interface  | < +
                                  +----------------+
```

---

## 🔌 Communication Protocols

### 1. JSON-RPC 2.0 (over HTTP and WebSocket)

Used for:

* Command issuance (open/close/trailing etc.)
* State queries (positions, account state)

### 2. WebSocket (PubSub)

Used for:

* Real-time updates (prices, positions, funding rates)
* TUI & Frontend push notifications

---

## 📦 Module Layout (Server)

```bash
gmxbot-server/
├── main.go              # RPC/WebSocket listener
├── api/                 # RPC method handlers
│   └── positions.go     # RPC: Open/Close/Query
├── core/                # Core logic modules
│   ├── pricing/         # Fee, funding, swap calculations
│   ├── positions/       # PnL, SL/TP, Trailing
│   └── assets/          # Price fetcher
├── ws/                  # WebSocket server/pubsub
│   └── dispatcher.go    # Subscription manager
└── store/               # In-memory and/or persistent store
```

## 📦 Module Layout (Client)

```bash
gmxbot-client/
├── main.go              # CLI command entry
├── tui/                 # Bubbletea/Charm UI
├── rpc/                 # JSON-RPC methods
├── ws/                  # WS subscriber
└── config/              # Strategy configuration loader
```

---

## 🤖 Automation Engine

### Features:

* Configurable strategy modules (e.g., breakout, trend-following)
* Signal processing (price movements, funding, volume)
* Automated PnL-based exit logic

### Modes:

* **Sim Mode**: Backtest against historical prices
* **Auto Mode**: Live trades based on rules

### Config Example (YAML/JSON)

```yaml
strategy: trailing-tp
market: ETH-USD
leverage: 5
risk: 0.02
sl: 2%
tp: 10%
trailingTrigger: 5%
trailingBuffer: 3%
```

---

## 🧪 Testing Strategy

* Full integration test suite via Go test
* CLI tests: `gmxbot-client test --all`
* RPC+WS validation tests with mocks
* Strategy dry-runs

---

## 🔐 Security

* Role-based client auth (API keys)
* Rate limiting
* Panic recovery and position sync

---

## 🛠 Tech Stack

* Go 1.24
* WebSocket: gorilla/websocket
* JSON-RPC: gRPC-gateway or go-jsonrpc
* TUI: charmbracelet/bubbletea
* Frontend: React or Vue (optional integration)

---

## ✅ Roadmap (Milestones)

| Week | Deliverable                               |
| ---- | ----------------------------------------- |
| 1    | Price + Position modules, JSON-RPC API    |
| 2    | TUI Client and WebSocket PubSub           |
| 3    | Auto Mode + SL/TP/Trailing engine         |
| 4    | Web Frontend + CLI sync, final test suite |

---

## 🔄 Next Steps

* Finalize `Position` struct contract
* Implement `OpenPosition`, `ClosePosition`, `UpdateTrailingStop`
* Bootstrap CLI and TUI shell
* Build server RPC router

