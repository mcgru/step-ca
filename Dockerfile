FROM smallstep/step-ca:latest

USER root
RUN apk add --no-cache postgresql-client
COPY scripts/entrypoint.sh /
RUN chmod +x /entrypoint.sh
USER step

ENTRYPOINT ["/entrypoint.sh"]
