import json
import logging

from fastapi.testclient import TestClient


def test_requests_are_logged_as_json(client: TestClient, capsys) -> None:
    client.get("/health")
    lines = [json.loads(line) for line in capsys.readouterr().out.splitlines() if line]
    request_logs = [line for line in lines if line["message"] == "request"]
    assert request_logs, lines
    entry = request_logs[-1]
    assert entry["path"] == "/health"
    assert entry["status"] == 200
    assert entry["env"] == "test"
    assert entry["git_sha"] == "abc1234"
    assert "duration_ms" in entry


def test_exceptions_are_serialized(client: TestClient, capsys) -> None:
    try:
        raise ValueError("boom")
    except ValueError:
        logging.getLogger("tasks_api").exception("falló algo")
    entry = json.loads(capsys.readouterr().out.splitlines()[-1])
    assert entry["level"] == "ERROR"
    assert "ValueError: boom" in entry["exception"]
