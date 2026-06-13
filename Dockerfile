FROM smallstep/step-ca:latest

USER root
COPY scripts/entrypoint.sh /
RUN chmod +x /entrypoint.sh
USER step

ENTRYPOINT ["/entrypoint.sh"]
