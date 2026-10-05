"""Configuración por variables de entorno (12 factor app).

Ningún valor sensible tiene default: los secretos llegan como variables de entorno
que ECS inyecta en tiempo de ejecución desde Secrets Manager.
"""

from functools import lru_cache
from typing import Literal

from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="APP_", case_sensitive=False)

    # Nombre del ambiente donde corre la tarea (dev, staging, prod, local).
    env: str = "local"
    # Versión semántica de la app y hash del commit. Se fijan en la imagen al construirla
    # (build args), así la misma imagen reporta lo mismo en los tres ambientes.
    version: str = "0.0.0-dev"
    git_sha: str = "unknown"
    log_level: str = "INFO"
    # Token que exigen las operaciones de escritura. Si no se define, la escritura queda abierta
    # (útil en desarrollo local); en ECS siempre se inyecta desde Secrets Manager.
    api_token: SecretStr | None = None
    # memory: cada proceso guarda sus datos (desarrollo y pruebas).
    # dynamodb: datos compartidos entre todas las tareas (ambientes desplegados). Las
    # credenciales y el endpoint los resuelve boto3 (rol de la tarea en ECS).
    storage: Literal["memory", "dynamodb"] = "memory"
    dynamodb_table: str | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()
