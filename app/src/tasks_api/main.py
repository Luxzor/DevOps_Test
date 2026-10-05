import logging
import secrets
import time
from collections.abc import Awaitable, Callable
from typing import Annotated
from uuid import UUID

from fastapi import Depends, FastAPI, Header, HTTPException, Request, Response, status

from tasks_api.config import Settings, get_settings
from tasks_api.logging_config import configure_logging
from tasks_api.models import Health, Task, TaskCreate, TaskUpdate, VersionInfo
from tasks_api.repository import DynamoDBTaskRepository, InMemoryTaskRepository, TaskRepository

logger = logging.getLogger("tasks_api")


def build_repository(settings: Settings) -> TaskRepository:
    if settings.storage == "dynamodb":
        if not settings.dynamodb_table:
            raise ValueError("APP_DYNAMODB_TABLE es obligatorio con APP_STORAGE=dynamodb")
        return DynamoDBTaskRepository.from_table_name(settings.dynamodb_table)
    return InMemoryTaskRepository()


def create_app(
    settings: Settings | None = None, repository: TaskRepository | None = None
) -> FastAPI:
    settings = settings or get_settings()
    repo = repository or build_repository(settings)
    configure_logging(
        settings.log_level,
        {"service": "tasks-api", "env": settings.env, "git_sha": settings.git_sha},
    )

    app = FastAPI(title="Tasks API", version=settings.version)

    @app.middleware("http")
    async def access_log(
        request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        start = time.perf_counter()
        response = await call_next(request)
        logger.info(
            "request",
            extra={
                "method": request.method,
                "path": request.url.path,
                "status": response.status_code,
                "duration_ms": round((time.perf_counter() - start) * 1000, 2),
            },
        )
        return response

    def require_token(x_api_key: Annotated[str | None, Header()] = None) -> None:
        expected = settings.api_token
        if expected is None:
            return
        if x_api_key is None or not secrets.compare_digest(x_api_key, expected.get_secret_value()):
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid or missing X-API-Key")

    write_guard = [Depends(require_token)]

    @app.get("/health", response_model=Health, tags=["ops"])
    def health() -> Health:
        return Health(status="ok")

    @app.get("/version", response_model=VersionInfo, tags=["ops"])
    def version() -> VersionInfo:
        return VersionInfo(
            version=settings.version, commit=settings.git_sha, environment=settings.env
        )

    @app.get("/tasks", response_model=list[Task], tags=["tasks"])
    def list_tasks() -> list[Task]:
        return repo.list()

    @app.post(
        "/tasks",
        response_model=Task,
        status_code=status.HTTP_201_CREATED,
        dependencies=write_guard,
        tags=["tasks"],
    )
    def create_task(data: TaskCreate) -> Task:
        return repo.create(data)

    @app.get("/tasks/{task_id}", response_model=Task, tags=["tasks"])
    def get_task(task_id: UUID) -> Task:
        task = repo.get(task_id)
        if task is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "task not found")
        return task

    @app.patch("/tasks/{task_id}", response_model=Task, dependencies=write_guard, tags=["tasks"])
    def update_task(task_id: UUID, data: TaskUpdate) -> Task:
        task = repo.update(task_id, data)
        if task is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "task not found")
        return task

    @app.delete(
        "/tasks/{task_id}",
        status_code=status.HTTP_204_NO_CONTENT,
        dependencies=write_guard,
        tags=["tasks"],
    )
    def delete_task(task_id: UUID) -> Response:
        if not repo.delete(task_id):
            raise HTTPException(status.HTTP_404_NOT_FOUND, "task not found")
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    logger.info("app configured", extra={"version": settings.version, "storage": settings.storage})
    return app
