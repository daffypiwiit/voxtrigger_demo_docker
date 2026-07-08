FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    sngrep \
    tcpdump \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY sngreprc /etc/sngrep/sngreprc
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
