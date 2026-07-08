FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV OPENSIPS_VERSION=3.6

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates gnupg2 wget curl postgresql-client \
    && rm -rf /var/lib/apt/lists/*

RUN wget -qO /usr/share/keyrings/opensips-org.gpg https://apt.opensips.org/opensips-org.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/opensips-org.gpg] https://apt.opensips.org bookworm ${OPENSIPS_VERSION}-releases" \
        > /etc/apt/sources.list.d/opensips.list \
    && echo "deb [signed-by=/usr/share/keyrings/opensips-org.gpg] https://apt.opensips.org bookworm cli-nightly" \
        >> /etc/apt/sources.list.d/opensips.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        opensips \
        opensips-postgres-module \
        opensips-postgres-dbschema \
        opensips-http-modules \
        opensips-carrierroute-module \
        opensips-cli \
    && rm -rf /var/lib/apt/lists/*

COPY opensips.cfg /etc/opensips/opensips.cfg
COPY opensips-cli.cfg /etc/opensips/opensips-cli.cfg
COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY postgres-seed/*.sql /opt/opensips-seed/

RUN chmod +x /docker-entrypoint.sh

EXPOSE 5060/udp 5060/tcp 5070/udp 8888/tcp

ENTRYPOINT ["/docker-entrypoint.sh"]

RUN ln -s /usr/share/opensips/postgres /usr/share/opensips/postgresql
