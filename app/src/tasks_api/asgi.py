"""Punto de entrada para uvicorn: `uvicorn tasks_api.asgi:app`."""

from tasks_api.main import create_app

app = create_app()
