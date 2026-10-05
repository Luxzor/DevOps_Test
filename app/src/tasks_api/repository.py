"""Almacenamiento de tareas.

- InMemoryTaskRepository: para desarrollo y pruebas; cada proceso tiene sus propios datos.
- DynamoDBTaskRepository: para los ambientes desplegados. Con dos o más tareas de ECS detrás
  del balanceador, los datos deben vivir fuera del contenedor (app sin estado, 12 factor).

Las rutas dependen solo del protocolo TaskRepository, así que cambiar de almacenamiento
(por ejemplo a RDS PostgreSQL en la fase 2) no toca la API.
"""

import threading
from datetime import UTC, datetime
from typing import TYPE_CHECKING, Any, Protocol
from uuid import UUID, uuid4

import boto3

from tasks_api.models import Task, TaskCreate, TaskUpdate

if TYPE_CHECKING:
    from mypy_boto3_dynamodb.service_resource import Table


class TaskRepository(Protocol):
    def list(self) -> list[Task]: ...
    def get(self, task_id: UUID) -> Task | None: ...
    def create(self, data: TaskCreate) -> Task: ...
    def update(self, task_id: UUID, data: TaskUpdate) -> Task | None: ...
    def delete(self, task_id: UUID) -> bool: ...


class InMemoryTaskRepository:
    def __init__(self) -> None:
        self._tasks: dict[UUID, Task] = {}
        self._lock = threading.Lock()

    def list(self) -> list[Task]:
        with self._lock:
            return sorted(self._tasks.values(), key=lambda t: t.created_at)

    def get(self, task_id: UUID) -> Task | None:
        with self._lock:
            return self._tasks.get(task_id)

    def create(self, data: TaskCreate) -> Task:
        now = datetime.now(UTC)
        task = Task(id=uuid4(), created_at=now, updated_at=now, **data.model_dump())
        with self._lock:
            self._tasks[task.id] = task
        return task

    def update(self, task_id: UUID, data: TaskUpdate) -> Task | None:
        with self._lock:
            current = self._tasks.get(task_id)
            if current is None:
                return None
            changes = data.model_dump(exclude_unset=True)
            updated = current.model_copy(update={**changes, "updated_at": datetime.now(UTC)})
            self._tasks[task_id] = updated
            return updated

    def delete(self, task_id: UUID) -> bool:
        with self._lock:
            return self._tasks.pop(task_id, None) is not None


class DynamoDBTaskRepository:
    def __init__(self, table: "Table") -> None:
        self._table = table

    @classmethod
    def from_table_name(cls, name: str) -> "DynamoDBTaskRepository":
        return cls(boto3.resource("dynamodb").Table(name))

    @staticmethod
    def _to_item(task: Task) -> dict[str, Any]:
        return task.model_dump(mode="json")

    @staticmethod
    def _from_item(item: dict[str, Any]) -> Task:
        return Task.model_validate(item)

    def list(self) -> list[Task]:
        # Scan alcanza para el volumen de este proyecto; con más datos se pagina o se usa
        # un índice. Se recorre la paginación para no perder elementos.
        items: list[dict[str, Any]] = []
        kwargs: dict[str, Any] = {}
        while True:
            page = self._table.scan(**kwargs)
            items.extend(page.get("Items", []))
            if "LastEvaluatedKey" not in page:
                break
            kwargs["ExclusiveStartKey"] = page["LastEvaluatedKey"]
        return sorted((self._from_item(i) for i in items), key=lambda t: t.created_at)

    def get(self, task_id: UUID) -> Task | None:
        item = self._table.get_item(Key={"id": str(task_id)}).get("Item")
        return self._from_item(item) if item else None

    def create(self, data: TaskCreate) -> Task:
        now = datetime.now(UTC)
        task = Task(id=uuid4(), created_at=now, updated_at=now, **data.model_dump())
        self._table.put_item(
            Item=self._to_item(task), ConditionExpression="attribute_not_exists(id)"
        )
        return task

    def update(self, task_id: UUID, data: TaskUpdate) -> Task | None:
        current = self.get(task_id)
        if current is None:
            return None
        changes = data.model_dump(exclude_unset=True)
        updated = current.model_copy(update={**changes, "updated_at": datetime.now(UTC)})
        try:
            self._table.put_item(
                Item=self._to_item(updated), ConditionExpression="attribute_exists(id)"
            )
        except self._table.meta.client.exceptions.ConditionalCheckFailedException:
            return None  # se borró entre la lectura y la escritura
        return updated

    def delete(self, task_id: UUID) -> bool:
        response = self._table.delete_item(Key={"id": str(task_id)}, ReturnValues="ALL_OLD")
        return "Attributes" in response
