FROM smallstep/step-ca:latest

COPY scripts/entrypoint.sh /
USER root
RUN chmod +x /entrypoint.sh
USER step

ENTRYPOINT ["/entrypoint.sh"]
