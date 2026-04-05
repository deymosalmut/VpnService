# Multi-stage build for Go microservices
# Usage: docker build --build-arg SERVICE=auth -t vpn-auth .

ARG SERVICE=auth

# ---- Build stage ----
FROM golang:1.22-alpine AS builder

ARG SERVICE
WORKDIR /src

# Cache dependencies
COPY go.mod go.sum* ./
RUN go mod download 2>/dev/null || true

# Copy source
COPY . .

# Build the specific service
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /app/${SERVICE} ./${SERVICE}/cmd/

# ---- Runtime stage ----
FROM alpine:3.20

ARG SERVICE
RUN apk --no-cache add ca-certificates tzdata

# Non-root user
RUN adduser -D -u 1001 appuser
USER appuser

WORKDIR /app
COPY --from=builder /app/${SERVICE} ./service

EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

ENTRYPOINT ["./service"]
