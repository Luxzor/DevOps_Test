"""Logs estructurados en JSON, una línea por evento, listos para CloudWatch Logs Insights."""

import json
import logging
import sys
from datetime import UTC, datetime
from typing import Any

# Atributos estándar de LogRecord que no se copian como campos extra.
_RESERVED = set(logging.LogRecord("", 0, "", 0, "", None, None).__dict__) | {
    "message",
    "color_message",  # duplicado con códigos ANSI que agrega uvicorn
}


class JsonFormatter(logging.Formatter):
    def __init__(self, static_fields: dict[str, str] | None = None) -> None:
        super().__init__()
        self._static = static_fields or {}

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.fromtimestamp(record.created, UTC).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            **self._static,
        }
        for key, value in record.__dict__.items():
            if key not in _RESERVED and not key.startswith("_"):
                payload[key] = value
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str)


class _StdoutHandler(logging.StreamHandler):  # type: ignore[type-arg]
    """Escribe siempre en el sys.stdout vigente (los contenedores envían stdout a CloudWatch)."""

    @property
    def stream(self) -> Any:
        return sys.stdout

    @stream.setter
    def stream(self, _value: Any) -> None:
        pass


def configure_logging(level: str, static_fields: dict[str, str]) -> None:
    handler = _StdoutHandler()
    handler.setFormatter(JsonFormatter(static_fields))
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level.upper())
    # uvicorn trae su propio access log en texto plano; lo reemplaza el middleware de la app.
    logging.getLogger("uvicorn.access").disabled = True
    for name in ("uvicorn", "uvicorn.error"):
        logging.getLogger(name).handlers = []
        logging.getLogger(name).propagate = True
