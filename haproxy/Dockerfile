FROM haproxy:3.0

USER root

COPY haproxy.cfg.template /usr/local/etc/haproxy/haproxy.cfg.template
COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
