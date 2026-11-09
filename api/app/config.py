"""Application settings read from environment variables only."""

import os
from dataclasses import dataclass

DEFAULT_HOST = "localhost"
DEFAULT_PORT = 5432
DEFAULT_USER = "app_rw"


@dataclass(frozen=True)
class Settings:
    host: str
    port: int
    dbname: str
    user: str
    password: str

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            host=os.environ.get("POSTGRES_HOST", DEFAULT_HOST),
            port=int(os.environ.get("POSTGRES_PORT", DEFAULT_PORT)),
            dbname=_required("POSTGRES_DB"),
            user=os.environ.get("DB_USER", DEFAULT_USER),
            password=_required("DB_PASSWORD"),
        )


def _required(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"Falta la variable de entorno obligatoria {name}")
    return value
