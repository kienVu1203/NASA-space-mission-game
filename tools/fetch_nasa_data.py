"""Fetch NASA data and write JSON files into ../data/. Fill in on event day."""
import json
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data"


def write(name: str, rows: list) -> None:
    (DATA / name).write_text(json.dumps(rows, indent=2), encoding="utf-8")


if __name__ == "__main__":
    print("TODO: fetch data and call write('destinations.json', rows)")
