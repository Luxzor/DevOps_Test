import pytest
from fastapi.testclient import TestClient

from tasks_api.config import Settings
from tasks_api.main import create_app

TOKEN = "test-token"  # noqa: S105 - valor de prueba, no es un secreto real


@pytest.fixture
def settings() -> Settings:
    return Settings(env="test", version="1.2.3", git_sha="abc1234", api_token=TOKEN)


@pytest.fixture
def client(settings: Settings) -> TestClient:
    return TestClient(create_app(settings))


@pytest.fixture
def auth() -> dict[str, str]:
    return {"X-API-Key": TOKEN}
