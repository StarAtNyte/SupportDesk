# ── Build stage ───────────────────────────────────────────────────────────────
FROM rust:1.86-slim AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*

# Cache dependencies separately from source
COPY Cargo.toml ./
RUN mkdir src && echo "fn main(){}" > src/main.rs && cargo build --release && rm -rf src

# Build actual source
COPY src ./src
COPY static ./static
COPY client-deploy ./client-deploy
# Touch main.rs so cargo rebuilds it
RUN touch src/main.rs && cargo build --release

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/target/release/rustdesk-support .
COPY --from=builder /app/static ./static

ENV PORT=3030
EXPOSE 3030

CMD ["./rustdesk-support"]
