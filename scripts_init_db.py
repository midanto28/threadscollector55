from pathlib import Path
import argparse
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent / "src"))

from threadscollector.db import init_db


def main() -> None:
    parser = argparse.ArgumentParser(description="Initialize threadscollector SQLite DB")
    parser.add_argument("--db", default="data/threads.db", help="Path to SQLite DB file")
    args = parser.parse_args()

    init_db(Path(args.db))
    print(f"Initialized DB at {args.db}")


if __name__ == "__main__":
    main()
