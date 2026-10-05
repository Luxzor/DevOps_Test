"""Prueba de integración: levanta uvicorn real en un puerto libre y habla HTTP con él.

Valida lo que las pruebas con TestClient no cubren: el punto de entrada `tasks_api.asgi`,
la lectura de configuración desde variables de entorno y el servidor ASGI de producción.
"""

import os
import pathlib
import socket
import subprocess
import sys
import time
from collections.abc import Iterator

import httpx
import pytest

pytestmark = pytest.mark.integration


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


@pytest.fixture(scope="module")
def base_url() -> Iterator[str]:
    port = free_port()
    env = {
        **os.environ,
        "APP_ENV": "integration",
        "APP_GIT_SHA": "feedbee",
        "APP_API_TOKEN": "integration-token",
        "PYTHONPATH": str(pathlib.Path(__file__).parents[2] / "src"),
    }
    proc = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "tasks_api.asgi:app", "--port", str(port)],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    url = f"http://127.0.0.1:{port}"
    try:
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            try:
                if httpx.get(f"{url}/health").status_code == 200:
                    break
            except httpx.TransportError:
                time.sleep(0.1)
        else:
            pytest.fail("uvicorn no respondió a tiempo")
        yield url
    finally:
        proc.terminate()
        proc.wait(timeout=10)


def test_version_comes_from_environment(base_url: str) -> None:
    body = httpx.get(f"{base_url}/version").json()
    assert body["commit"] == "feedbee"
    assert body["environment"] == "integration"


def test_crud_flow_over_http(base_url: str) -> None:
    auth = {"X-API-Key": "integration-token"}
    with httpx.Client(base_url=base_url, headers=auth) as http:
        created = http.post("/tasks", json={"title": "integración"})
        assert created.status_code == 201
        task_id = created.json()["id"]
        assert http.patch(f"/tasks/{task_id}", json={"done": True}).json()["done"] is True
        assert task_id in [t["id"] for t in http.get("/tasks").json()]
        assert http.delete(f"/tasks/{task_id}").status_code == 204
        assert http.get(f"/tasks/{task_id}").status_code == 404
    assert httpx.post(f"{base_url}/tasks", json={"title": "x"}).status_code == 401
