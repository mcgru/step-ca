FROM smallstep/step-ca:latest

USER root
RUN apk add --no-cache su-exec
COPY scripts/entrypoint.sh /
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
