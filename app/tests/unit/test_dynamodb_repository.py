"""El repositorio DynamoDB contra un DynamoDB simulado en memoria (moto)."""

from collections.abc import Iterator
from uuid import uuid4

import boto3
import pytest
from fastapi.testclient import TestClient
from moto import mock_aws

from tasks_api.config import Settings
from tasks_api.main import build_repository, create_app
from tasks_api.models import TaskCreate, TaskUpdate
from tasks_api.repository import DynamoDBTaskRepository

TABLE = "tasks-test"


@pytest.fixture
def repo(monkeypatch) -> Iterator[DynamoDBTaskRepository]:
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.delenv("AWS_ENDPOINT_URL", raising=False)
    with mock_aws():
        boto3.client("dynamodb").create_table(
            TableName=TABLE,
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        yield DynamoDBTaskRepository.from_table_name(TABLE)


def test_crud_roundtrip(repo: DynamoDBTaskRepository) -> None:
    task = repo.create(TaskCreate(title="persistir", description="en DynamoDB"))
    assert repo.get(task.id) == task

    updated = repo.update(task.id, TaskUpdate(done=True))
    assert updated is not None and updated.done is True
    assert updated.description == "en DynamoDB"
    assert repo.get(task.id) == updated

    assert repo.delete(task.id) is True
    assert repo.get(task.id) is None
    assert repo.delete(task.id) is False


def test_missing_task(repo: DynamoDBTaskRepository) -> None:
    assert repo.update(uuid4(), TaskUpdate(done=True)) is None


def test_list_paginates_and_sorts(repo: DynamoDBTaskRepository, monkeypatch) -> None:
    created = [repo.create(TaskCreate(title=f"t{i}")) for i in range(5)]
    original_scan = repo._table.scan

    def small_pages(**kwargs):  # fuerza varias páginas para probar la paginación
        return original_scan(Limit=2, **kwargs)

    monkeypatch.setattr(repo._table, "scan", small_pages)
    assert [t.id for t in repo.list()] == [t.id for t in created]


def test_concurrent_delete_during_update(repo: DynamoDBTaskRepository, monkeypatch) -> None:
    task = repo.create(TaskCreate(title="carrera"))
    original_get = repo.get

    def get_then_delete(task_id):
        found = original_get(task_id)
        repo._table.delete_item(Key={"id": str(task_id)})
        return found

    monkeypatch.setattr(repo, "get", get_then_delete)
    assert repo.update(task.id, TaskUpdate(done=True)) is None


def test_app_uses_dynamodb_when_configured(repo: DynamoDBTaskRepository) -> None:
    settings = Settings(storage="dynamodb", dynamodb_table=TABLE, api_token=None)
    client = TestClient(create_app(settings))
    task_id = client.post("/tasks", json={"title": "compartida"}).json()["id"]
    # Otra instancia de la app (otra tarea de ECS) ve el mismo dato.
    other = TestClient(create_app(settings))
    assert other.get(f"/tasks/{task_id}").status_code == 200


def test_dynamodb_requires_table_name() -> None:
    with pytest.raises(ValueError, match="APP_DYNAMODB_TABLE"):
        build_repository(Settings(storage="dynamodb"))
