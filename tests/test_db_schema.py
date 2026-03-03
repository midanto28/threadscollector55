import sqlite3
import tempfile
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from threadscollector.db import init_db


class SchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tempdir.name) / "threads.db"
        init_db(self.db_path)

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def _conn(self):
        return sqlite3.connect(self.db_path)

    def test_core_tables_exist(self):
        expected = {"posts", "tags", "post_tags", "media", "posts_fts"}
        with self._conn() as conn:
            rows = conn.execute(
                "SELECT name FROM sqlite_master WHERE type IN ('table', 'virtual table')"
            ).fetchall()
        names = {r[0] for r in rows}
        self.assertTrue(expected.issubset(names))

    def test_unique_constraint_on_content_hash(self):
        with self._conn() as conn:
            conn.execute(
                "INSERT INTO posts(text, created_at, content_hash, permalink) VALUES (?, ?, ?, ?)",
                ("hello", "2024-01-01T00:00:00Z", "hash1", "https://example.com/1"),
            )
            with self.assertRaises(sqlite3.IntegrityError):
                conn.execute(
                    "INSERT INTO posts(text, created_at, content_hash, permalink) VALUES (?, ?, ?, ?)",
                    ("hello2", "2024-01-02T00:00:00Z", "hash1", "https://example.com/2"),
                )

    def test_fts_trigger_syncs_insert(self):
        with self._conn() as conn:
            conn.execute(
                "INSERT INTO posts(text, created_at, content_hash, permalink) VALUES (?, ?, ?, ?)",
                ("threads search keyword", "2024-01-01T00:00:00Z", "hash3", "https://example.com/3"),
            )
            rows = conn.execute(
                "SELECT rowid FROM posts_fts WHERE posts_fts MATCH ?", ("keyword",)
            ).fetchall()
        self.assertEqual(len(rows), 1)


if __name__ == "__main__":
    unittest.main()
