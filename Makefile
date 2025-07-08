build-bot:
	@echo "Building bot"
	@docker compose run mev-bot-v2-dev \
		sh -c "clear && go mod tidy && go mod vendor && go build -o bin/mev-bot-v2-alpha cmd/bot-v2-alpha/main.go"

build-contracts:
	@docker compose run smart-contracts-dev \
		'bash -c "forge build --force --via-ir"' 

generate-contract-bindings:
	@sh -c "./generate_bindings.sh"

run-dev: 
	@${MAKE} build-bot && \
		${MAKE} run-bot 

run-bot:
       @echo "Running bot with local anvil"
       @docker compose up anvil mev-bot-v2-dev


gen-codebase:
	@codebase-gen -dir ./smart-contracts/ \
		-iname "*.sol" -out codebase_sol.txt  \
		-exclude "*/lib/*" && \
		codebase-gen -dir ./bot/ -iname "*.go" \
		-out codebase_go.txt  -exclude "*/vendor/*" \
		-exclude "*/contracts/bindings/*" && \
		codebase-gen -dir ./bot/contracts -iname "*.go" \
		-out contracts_go.txt  -exclude "*/vendor/*"

cache-clean:
	@go clean -modcache

run-bot-client:
	@docker compose exec mev-bot-v2-dev  \
		bin/mev-bot-v2-alpha --mode executor

down:
	@docker compose down
setup:
       @command -v docker >/dev/null || (echo "Error: docker is not installed or not in PATH."; exit 1)
       @docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null || (echo "Error: Docker Compose is not installed."; exit 1)
       @if [ ! -f .env ]; then echo "Creating .env from sample" && cp .env.sample .env; fi
       @echo "Building development containers and installing dependencies"
       @docker compose pull --quiet anvil smart-contracts-dev
       @docker compose build mev-bot-v2-dev
       @docker compose run --rm smart-contracts-dev bash -c "forge install"
       @docker compose run --rm mev-bot-v2-dev sh -c "go mod tidy && go mod download"

test-bot:
	@docker compose run mev-bot-v2-dev sh -c "go test ./..."

test-contracts:
	@docker compose run smart-contracts-dev bash -c "forge test --fork-url $${MAINNET_RPC_URL} -vv"
