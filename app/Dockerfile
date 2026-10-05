# syntax=docker/dockerfile:1.7
# Imagen base fijada por digest: builds reproducibles y Dependabot propone las actualizaciones.

# ---------- Etapa 1: dependencias ----------
FROM python:3.12-slim@sha256:02108f5d322dd89f1c9e552442c25acb0543dfdbc455693a5599624f20d9155d AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /build
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Solo requirements.txt primero: la capa de dependencias se reutiliza mientras no cambien.
COPY requirements.txt .
RUN pip install --require-virtualenv -r requirements.txt

# ---------- Etapa 2: runtime ----------
FROM python:3.12-slim@sha256:02108f5d322dd89f1c9e552442c25acb0543dfdbc455693a5599624f20d9155d AS runtime

# Valores no secretos que identifican la build. Se fijan una vez y viajan con la imagen,
# por eso la misma imagen reporta el mismo commit en dev, staging y prod.
ARG GIT_SHA=unknown
ARG APP_VERSION=0.0.0-dev

LABEL org.opencontainers.image.title="tasks-api" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.version="${APP_VERSION}"

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    APP_GIT_SHA="${GIT_SHA}" \
    APP_VERSION="${APP_VERSION}" \
    PORT=8000

# Parches de seguridad del sistema publicados después de la imagen base.
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Usuario sin privilegios con UID fijo (las políticas de seguridad suelen exigir runAsNonRoot).
RUN groupadd --gid 10001 app \
    && useradd --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
# El código va en su propia capa, después de las dependencias, para aprovechar la caché.
COPY src/tasks_api ./tasks_api

USER 10001:10001
EXPOSE 8000

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import os,urllib.request; urllib.request.urlopen(f'http://127.0.0.1:{os.environ[\"PORT\"]}/health', timeout=2)"]

# Forma exec: uvicorn es PID 1 y recibe SIGTERM cuando ECS detiene la tarea.
CMD ["sh", "-c", "exec uvicorn tasks_api.asgi:app --host 0.0.0.0 --port ${PORT} --no-server-header --proxy-headers"]
