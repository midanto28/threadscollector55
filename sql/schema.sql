PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS posts (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  source_platform   TEXT NOT NULL DEFAULT 'threads',
  source_post_id    TEXT,
  permalink         TEXT,
  text              TEXT NOT NULL,
  created_at        TEXT NOT NULL,
  visibility        TEXT DEFAULT 'unknown',
  content_hash      TEXT NOT NULL,
  imported_at       TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at        TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(source_platform, source_post_id),
  UNIQUE(permalink),
  UNIQUE(content_hash)
);

CREATE TABLE IF NOT EXISTS tags (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  name              TEXT NOT NULL,
  normalized_name   TEXT NOT NULL,
  UNIQUE(normalized_name)
);

CREATE TABLE IF NOT EXISTS post_tags (
  post_id           INTEGER NOT NULL,
  tag_id            INTEGER NOT NULL,
  created_at        TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (post_id, tag_id),
  FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE,
  FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS media (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  post_id           INTEGER NOT NULL,
  media_type        TEXT NOT NULL,
  media_url         TEXT,
  local_path        TEXT,
  sort_order        INTEGER NOT NULL DEFAULT 0,
  width             INTEGER,
  height            INTEGER,
  created_at        TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(post_id, media_url),
  UNIQUE(post_id, local_path),
  FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_posts_created_at ON posts(created_at);
CREATE INDEX IF NOT EXISTS idx_posts_imported_at ON posts(imported_at);
CREATE INDEX IF NOT EXISTS idx_media_post_id ON media(post_id);

CREATE VIRTUAL TABLE IF NOT EXISTS posts_fts USING fts5(
  text,
  content='posts',
  content_rowid='id',
  tokenize='unicode61'
);

CREATE TRIGGER IF NOT EXISTS posts_ai AFTER INSERT ON posts BEGIN
  INSERT INTO posts_fts(rowid, text) VALUES (new.id, new.text);
END;

CREATE TRIGGER IF NOT EXISTS posts_ad AFTER DELETE ON posts BEGIN
  INSERT INTO posts_fts(posts_fts, rowid, text) VALUES ('delete', old.id, old.text);
END;

CREATE TRIGGER IF NOT EXISTS posts_au AFTER UPDATE OF text ON posts BEGIN
  INSERT INTO posts_fts(posts_fts, rowid, text) VALUES ('delete', old.id, old.text);
  INSERT INTO posts_fts(rowid, text) VALUES (new.id, new.text);
END;
