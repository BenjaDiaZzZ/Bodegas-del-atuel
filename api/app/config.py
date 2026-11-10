"""Application settings read from environment variables only."""

import os
from dataclasses import dataclass

DEFAULT_HOST = "localhost"
DEFAULT_PORT = 5432
DEFAULT_USER = "app_rw"
DEFAULT_SSLMODE = "prefer"
VALID_SSLMODES = frozenset(
    {"disable", "allow", "prefer", "require", "verify-ca", "verify-full"}
)


@dataclass(frozen=True)
class Settings:
    host: str
    port: int
    dbname: str
    user: str
    password: str
    sslmode: str

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            host=os.environ.get("POSTGRES_HOST", DEFAULT_HOST),
            port=_port_from_env(),
            dbname=_required("POSTGRES_DB"),
            user=os.environ.get("DB_USER", DEFAULT_USER),
            password=_required("DB_PASSWORD"),
            sslmode=_sslmode_from_env(),
        )


def _port_from_env() -> int:
    raw = os.environ.get("POSTGRES_PORT")
    if raw is None:
        return DEFAULT_PORT
    try:
        return int(raw)
    except ValueError:
        raise RuntimeError(
            f"La variable de entorno POSTGRES_PORT no es un entero valido: {raw}"
        ) from None


def _sslmode_from_env() -> str:
    raw = os.environ.get("POSTGRES_SSLMODE")
    if raw is None:
        return DEFAULT_SSLMODE
    if raw not in VALID_SSLMODES:
        raise RuntimeError(
            f"La variable de entorno POSTGRES_SSLMODE no es un modo SSL valido: {raw}"
        )
    return raw


def _required(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"Falta la variable de entorno obligatoria {name}")
    return value
