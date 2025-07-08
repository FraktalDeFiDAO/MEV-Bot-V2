FROM golang:1.24.4 as go-base
RUN go install github.com/ethereum/go-ethereum/cmd/abigen@latest

FROM go-base as go-dev

