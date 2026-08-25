# syntax=docker/dockerfile:1

# ---------- build stage ----------
FROM golang:1.25-alpine AS builder
WORKDIR /workspace

# Copy module manifest first so the dependency layer survives source-only edits.
COPY go.mod ./
RUN go mod download

# Copy only the source directories required to test and build the API.
COPY cmd/ ./cmd/
COPY internal/ ./internal/

# Exercise the test suite (not skipped) before producing the binary.
RUN go test ./...

# Statically link the binary so the final stage can be `scratch`.
RUN CGO_ENABLED=0 go build -buildvcs=false -o /out/inventory-api ./cmd/api

# ---------- runtime stage ----------
FROM scratch
COPY --from=builder /out/inventory-api /inventory-api
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/inventory-api"]