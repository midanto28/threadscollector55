from __future__ import annotations

import sqlite3
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def schema_path() -> Path:
    return _repo_root() / "sql" / "schema.sql"


def load_schema_sql() -> str:
    return schema_path().read_text(encoding="utf-8")


def init_db(db_path: str | Path) -> None:
    path = Path(db_path)
    path.parent.mkdir(parents=True, exist_ok=True)

    with sqlite3.connect(path) as conn:
        conn.executescript(load_schema_sql())
        conn.commit()
