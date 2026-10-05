from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=2000)
    done: bool = False


class TaskUpdate(BaseModel):
    """Actualización parcial: solo se modifican los campos enviados."""

    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=2000)
    done: bool | None = None


class Task(BaseModel):
    id: UUID
    title: str
    description: str | None
    done: bool
    created_at: datetime
    updated_at: datetime


class Health(BaseModel):
    status: str


class VersionInfo(BaseModel):
    version: str
    commit: str
    environment: str
