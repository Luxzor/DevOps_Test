# Runner autohospedado de GitHub Actions para la simulación local.
# Imagen oficial del runner (incluye Docker CLI, buildx, git, jq y curl) más AWS CLI v2.
FROM ghcr.io/actions/actions-runner:2.338.2@sha256:759a1d94a15b05941aba5196974ff43fe15b4cbba29b694b35cbc32a1166b232

USER root
RUN ARCH="$(uname -m)" \
    && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o /tmp/awscli.zip \
    && unzip -q /tmp/awscli.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscli.zip

COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh

# El entrypoint arranca como root solo para alinear el grupo del socket de Docker
# y luego ejecuta el runner como el usuario sin privilegios `runner`.
ENTRYPOINT ["/entrypoint.sh"]
