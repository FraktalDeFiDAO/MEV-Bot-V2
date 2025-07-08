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
	@echo "Running bot"
	@docker compose up mev-bot-v2-dev


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
	