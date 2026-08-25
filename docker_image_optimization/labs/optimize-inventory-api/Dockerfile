# syntax=docker/dockerfile:1
# Replace this baseline-style Dockerfile with your optimized implementation.
# Keep the file name `Dockerfile`.
FROM golang:1.25-alpine
WORKDIR /workspace
COPY . .
RUN go mod download
RUN go test ./...
RUN CGO_ENABLED=0 go build -buildvcs=false -o /usr/local/bin/inventory-api ./cmd/api
EXPOSE 8080
CMD ["/usr/local/bin/inventory-api"]
