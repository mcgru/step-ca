FROM smallstep/step-ca:latest

COPY scripts/entrypoint.sh /
USER root
RUN apk add --no-cache su-exec && chmod +x /entrypoint.sh
USER step

ENTRYPOINT ["/entrypoint.sh"]
