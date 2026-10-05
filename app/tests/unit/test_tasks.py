from uuid import uuid4

import pytest
from fastapi.testclient import TestClient


def create(client: TestClient, auth: dict[str, str], **body: object) -> dict:
    response = client.post("/tasks", json={"title": "Escribir pruebas", **body}, headers=auth)
    assert response.status_code == 201
    return response.json()


def test_create_and_get(client: TestClient, auth: dict[str, str]) -> None:
    task = create(client, auth, description="cobertura mínima 80%")
    assert task["done"] is False
    response = client.get(f"/tasks/{task['id']}")
    assert response.status_code == 200
    assert response.json() == task


def test_list_is_ordered_by_creation(client: TestClient, auth: dict[str, str]) -> None:
    first = create(client, auth, title="primera")
    second = create(client, auth, title="segunda")
    ids = [t["id"] for t in client.get("/tasks").json()]
    assert ids == [first["id"], second["id"]]


def test_partial_update(client: TestClient, auth: dict[str, str]) -> None:
    task = create(client, auth, description="sin cambios")
    response = client.patch(f"/tasks/{task['id']}", json={"done": True}, headers=auth)
    assert response.status_code == 200
    body = response.json()
    assert body["done"] is True
    assert body["description"] == "sin cambios"
    assert body["updated_at"] >= task["updated_at"]


def test_delete(client: TestClient, auth: dict[str, str]) -> None:
    task = create(client, auth)
    assert client.delete(f"/tasks/{task['id']}", headers=auth).status_code == 204
    assert client.get(f"/tasks/{task['id']}").status_code == 404


@pytest.mark.parametrize(
    ("method", "body"),
    [("get", None), ("patch", {"done": True}), ("delete", None)],
)
def test_missing_task_returns_404(
    client: TestClient, auth: dict[str, str], method: str, body: dict | None
) -> None:
    kwargs = {"headers": auth} | ({"json": body} if body else {})
    response = getattr(client, method)(f"/tasks/{uuid4()}", **kwargs)
    assert response.status_code == 404


@pytest.mark.parametrize("payload", [{}, {"title": ""}, {"title": "x" * 201}])
def test_validation_errors(client: TestClient, auth: dict[str, str], payload: dict) -> None:
    assert client.post("/tasks", json=payload, headers=auth).status_code == 422


@pytest.mark.parametrize("headers", [{}, {"X-API-Key": "incorrecto"}])
def test_writes_require_token(client: TestClient, headers: dict[str, str]) -> None:
    assert client.post("/tasks", json={"title": "x"}, headers=headers).status_code == 401


def test_reads_do_not_require_token(client: TestClient) -> None:
    assert client.get("/tasks").status_code == 200
