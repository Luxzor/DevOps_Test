from fastapi.testclient import TestClient

from tasks_api.config import Settings
from tasks_api.main import create_app


def test_health(client: TestClient) -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_version_reports_commit_and_environment(client: TestClient) -> None:
    response = client.get("/version")
    assert response.status_code == 200
    assert response.json() == {"version": "1.2.3", "commit": "abc1234", "environment": "test"}


def test_settings_read_from_environment(monkeypatch) -> None:
    monkeypatch.setenv("APP_ENV", "staging")
    monkeypatch.setenv("APP_GIT_SHA", "deadbeef")
    monkeypatch.setenv("APP_API_TOKEN", "from-secrets-manager")
    settings = Settings()
    assert settings.env == "staging"
    assert settings.git_sha == "deadbeef"
    assert settings.api_token is not None
    # El token nunca aparece en texto plano al imprimir la configuración.
    assert "from-secrets-manager" not in repr(settings)


def test_without_token_writes_are_open() -> None:
    client = TestClient(create_app(Settings(api_token=None)))
    response = client.post("/tasks", json={"title": "abierta"})
    assert response.status_code == 201
