# threadscollector55
내가 내 Threads 글 보기 편하려고 만드는 프로젝트

## 프로젝트 목표
Threads는 최신순 탐색 중심이라 예전 글을 다시 찾기 어렵다. 이 프로젝트의 목표는 **내가 접근 가능한 내 글**을 빠르게 찾는 **개인 아카이브/검색 도구**를 만드는 것이다.

- 대상: 개인 사용자 1인(Local-first)
- 핵심 가치: 빠른 재탐색(검색/필터/정렬)
- 비목표: 비공식 API 우회, 로그인 자동화, 타인 데이터 대량 수집

---

## "수집 시작" 동작 정의 (MVP 확정)
"수집 시작"은 아래 2가지 입력 경로만 지원한다.

### 1) 공식 데이터 내보내기 업로드
1. 사용자가 Threads/Meta에서 받은 내보내기 파일(예: ZIP)을 업로드
2. 앱이 ZIP 내부 JSON/HTML 파일을 탐색
3. 파서가 게시물 단위로 `text`, `created_at`, `permalink`, `media`를 추출
4. DB에 upsert(중복 병합) 저장
5. 저장 결과(신규/중복/실패 건수) 리포트 출력

### 2) 수동 입력
1. 사용자가 `링크 + 본문 + 날짜`를 입력
2. 앱이 기본 유효성 검사(필수값/날짜 형식)
3. DB에 저장(중복 키 충돌 시 업데이트 또는 건너뜀)

### 절대 포함하지 않는 것
- 자동 로그인
- 세션/쿠키 우회 사용
- 비공식 엔드포인트 호출

---

## 데이터 모델 (SQLite 스키마 초안)
아래는 MVP에서 바로 사용 가능한 스키마다.

### 설계 포인트
- 게시물 고유성: `source_platform + source_post_id` 또는 `permalink`
- 태그 정규화: `tags` 분리 + `post_tags` M:N
- 미디어 분리: `media` 테이블로 1:N
- 검색 최적화: `posts_fts`(FTS5) + 날짜 인덱스

### SQL 예시
```sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS posts (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  source_platform   TEXT NOT NULL DEFAULT 'threads',
  source_post_id    TEXT,                           -- 원본에서 추출 가능할 때만 저장
  permalink         TEXT,                           -- 원문 링크
  text              TEXT NOT NULL,
  created_at        TEXT NOT NULL,                  -- ISO-8601 UTC 권장
  visibility        TEXT DEFAULT 'unknown',
  content_hash      TEXT NOT NULL,                  -- 본문/링크 기반 해시
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
  media_type        TEXT NOT NULL,                  -- image | video | etc
  media_url         TEXT,                           -- 원본 참조 URL
  local_path        TEXT,                           -- 로컬 저장 경로(선택)
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

-- FTS5 가상 테이블 (external content)
CREATE VIRTUAL TABLE IF NOT EXISTS posts_fts USING fts5(
  text,
  content='posts',
  content_rowid='id',
  tokenize='unicode61'
);

-- 동기화 트리거
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
```

---

## 검색 설계 (SQLite FTS5)
요구사항: 키워드 검색 + 날짜 범위 + 최신/오래된순 + 상세 조회

### 1) 키워드 + 날짜 범위 + 정렬
```sql
-- :q, :from_date, :to_date, :sort('newest'|'oldest'), :limit, :offset
SELECT
  p.id,
  p.created_at,
  p.permalink,
  snippet(posts_fts, 0, '[', ']', ' … ', 12) AS snippet,
  bm25(posts_fts) AS score
FROM posts_fts
JOIN posts p ON p.id = posts_fts.rowid
WHERE posts_fts MATCH :q
  AND p.created_at >= :from_date
  AND p.created_at <  :to_date
ORDER BY
  CASE WHEN :sort = 'newest' THEN p.created_at END DESC,
  CASE WHEN :sort = 'oldest' THEN p.created_at END ASC,
  score ASC
LIMIT :limit OFFSET :offset;
```

### 2) 키워드 없이 날짜 목록 조회(타임라인 탐색)
```sql
SELECT id, created_at, permalink, text
FROM posts
WHERE created_at >= :from_date
  AND created_at <  :to_date
ORDER BY
  CASE WHEN :sort = 'newest' THEN created_at END DESC,
  CASE WHEN :sort = 'oldest' THEN created_at END ASC
LIMIT :limit OFFSET :offset;
```

### 3) 상세 조회
```sql
SELECT p.*, group_concat(t.name, ', ') AS tags
FROM posts p
LEFT JOIN post_tags pt ON pt.post_id = p.id
LEFT JOIN tags t ON t.id = pt.tag_id
WHERE p.id = :post_id
GROUP BY p.id;

SELECT * FROM media WHERE post_id = :post_id ORDER BY sort_order ASC, id ASC;
```

---

## MVP 체크리스트 (구현 범위 고정)
- [ ] Import 1종 구현
  - [ ] 공식 내보내기 ZIP(JSON/HTML) 파싱 **또는**
  - [ ] 수동 입력 폼(링크/본문/날짜)
- [ ] SQLite 저장
  - [ ] `posts`, `tags`, `post_tags`, `media` 생성
  - [ ] UNIQUE 제약 기반 중복 방지
- [ ] 검색
  - [ ] FTS5 키워드 검색
  - [ ] 날짜 범위 필터
  - [ ] 최신순/오래된순 정렬
- [ ] UI
  - [ ] 목록 화면(검색창 + 날짜 필터 + 정렬)
  - [ ] 상세 화면(본문 + 태그 + 미디어)

---

## Threat Model (보안/정책 준수)
- 로그인 토큰/세션 쿠키 저장 안 함
- 약관 우회/비공식 API 호출 기능 없음
- 로컬 우선(Local-first): 기본 데이터 저장 위치는 사용자 로컬 디스크
- 민감정보 최소 수집: 필요한 메타데이터만 저장

---

## 다음 구현 단위 제안 (커밋 단위 4개)
1. **commit 1: db/schema**
   - SQLite 마이그레이션 추가 (`posts/tags/post_tags/media/posts_fts`)
   - 인덱스/트리거/UNIQUE 제약 포함
2. **commit 2: import/manual + export parser(1종)**
   - 수동 입력 API/폼
   - ZIP 파서 1종(JSON 또는 HTML) + upsert
3. **commit 3: search API**
   - FTS5 검색 엔드포인트
   - 날짜 필터/정렬/페이지네이션/상세 조회
4. **commit 4: MVP UI**
   - 목록 화면(검색, 필터, 정렬)
   - 상세 화면(본문, 태그, 미디어)

---

## 저장/배포 가이드
결론: 초기에는 서버 없이 로컬 SQLite로 충분하다.

- 텍스트 중심 데이터는 가볍다.
- 용량 급증 원인은 이미지/동영상 원본 보관이다.
- MVP는 원문 텍스트 + 메타데이터 중심 저장을 기본으로 한다.

서버 전환은 아래 조건 충족 시 검토:
- 다중 사용자
- 다기기 실시간 동기화
- 대규모 미디어 원본 장기 보관


## 대화/문서/코딩 진행 원칙
질문한 내용에 대한 답:
- **계속 README만 하는 게 아니다.** README는 방향 고정용이고, 코딩은 별도 단계에서 바로 진행한다.
- **모든 대화를 README에 반영하지 않는다.** 문서 반영은 "결정된 내용"만 한다.
- **대화 자체(아이디어 탐색/고민/질문)는 자유롭게 하고**, 구현 항목이 확정되면 그때 커밋 단위로 개발한다.

### 어떤 대화가 README에 반영되나?
아래 3가지 중 하나일 때만 반영:
1. 제품 범위/정책 같은 **장기 기준**이 바뀜
2. 구현자가 반드시 따라야 하는 **명세**가 확정됨
3. 팀 합의된 **운영 규칙**이 생김

그 외 일반 질의응답/아이디어 토론은 README에 자동 반영하지 않는다.

### 코딩 시작 트리거 (이 한 줄이면 충분)
아래처럼 말하면 바로 코드 작업으로 전환:
> "README는 여기까지. 이제 commit 1(db/schema)부터 실제 코드로 구현해줘."

### 권장 진행 루프
1) 짧은 대화로 기능 확정
2) 코딩(작은 커밋)
3) 테스트
4) PR 요약
5) 다음 기능

즉, 문서는 기준만 잡고, 실제 진도는 **코드 + 테스트** 중심으로 진행한다.

---

## 코딩 시작 상태 (현재)
이번 단계에서 문서만이 아니라 **실제 DB 스키마 코드**를 추가했다.

- `sql/schema.sql`: SQLite + FTS5 + 트리거 정의
- `src/threadscollector/db.py`: 스키마 로딩/DB 초기화 함수
- `scripts_init_db.py`: DB 파일 생성 스크립트
- `tests/test_db_schema.py`: 스키마/UNIQUE/FTS 동작 테스트

실행 예시:
```bash
python scripts_init_db.py --db data/threads.db
python -m unittest discover -s tests -v
```

---

## GitHub에 변경이 안 보일 때 (필수 체크)
현재처럼 GitHub에서 변화가 안 보이는 가장 흔한 이유는 **원격(remote)이 연결되지 않았거나 push를 안 한 경우**다.

### 1) 상태 확인
```bash
git remote -v
git branch --show-current
git log --oneline -n 5
```

- `git remote -v` 결과가 비어 있으면 원격이 없는 상태다.
- 이 경우 로컬 커밋은 있어도 GitHub 저장소에는 반영되지 않는다.

### 2) 원격 연결
```bash
git remote add origin <YOUR_GITHUB_REPO_URL>
```

### 3) 현재 브랜치 push
```bash
git push -u origin work
```

### 4) GitHub에서 확인
- 저장소의 `work` 브랜치 또는 PR 탭에서 커밋 반영 확인

핵심: **Codex가 로컬에서 커밋/PR 내용을 준비해도, 원격 push 전에는 GitHub 화면이 바뀌지 않는다.**
