# syntax=docker/dockerfile:1
FROM debian:bookworm-slim

ARG FREESWITCH_GIT_URL=https://bitbucket.org/piwiit/pwt.freeswitch_vxt.git
ARG FREESWITCH_GIT_BRANCH=development
ARG FREESWITCH_GIT_USER=

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates gnupg2 wget lsb-release lua-cjson git \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=secret,id=signalwire_token \
    TOKEN=$(cat /run/secrets/signalwire_token) \
    && wget -q --user=signalwire --password="$TOKEN" \
        -O /usr/share/keyrings/signalwire-freeswitch-repo.gpg \
        https://freeswitch.signalwire.com/repo/deb/debian-release/signalwire-freeswitch-repo.gpg \
    && echo "machine freeswitch.signalwire.com login signalwire password $TOKEN" > /etc/apt/auth.conf \
    && chmod 600 /etc/apt/auth.conf \
    && echo "deb [signed-by=/usr/share/keyrings/signalwire-freeswitch-repo.gpg] https://freeswitch.signalwire.com/repo/deb/debian-release/ bookworm main" \
        > /etc/apt/sources.list.d/freeswitch.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        freeswitch-meta-all freeswitch-mod-xml-curl freeswitch-mod-tone-stream \
    && rm -rf /var/lib/apt/lists/* /etc/apt/auth.conf

RUN --mount=type=secret,id=freeswitch_git_token \
    set -eux; \
    TOKEN=$(tr -d '\n' < /run/secrets/freeswitch_git_token || true); \
    if [ -n "$TOKEN" ] && [ -n "${FREESWITCH_GIT_USER}" ]; then \
        HOST_PATH="${FREESWITCH_GIT_URL#https://}"; \
        HOST_PATH="${HOST_PATH#http://}"; \
        CLONE_URL="https://${FREESWITCH_GIT_USER}:${TOKEN}@${HOST_PATH}"; \
    else \
        CLONE_URL="${FREESWITCH_GIT_URL}"; \
    fi; \
    git clone --depth 1 -b "${FREESWITCH_GIT_BRANCH}" "$CLONE_URL" /tmp/fs-config; \
    cp -a /tmp/fs-config/freeswitch/. /etc/freeswitch/; \
    cp -a /tmp/fs-config/scripts/. /usr/share/freeswitch/scripts/; \
    rm -rf /tmp/fs-config

COPY modules/ /usr/lib/freeswitch/mod/
COPY sip_profiles/external_0.xml /etc/freeswitch/sip_profiles/external_0.xml
COPY autoload_configs/event_socket.conf.xml /etc/freeswitch/autoload_configs/event_socket.conf.xml
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh \
    && mkdir -p /opt/cdr/vxt /etc/freeswitch/sip_profiles \
    && chown -R freeswitch:freeswitch /etc/freeswitch /usr/share/freeswitch/scripts /opt/cdr/vxt

EXPOSE 5080/udp 5080/tcp 8021/tcp

ENTRYPOINT ["/docker-entrypoint.sh"]
