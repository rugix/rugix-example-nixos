"""Serve the Rugix Apps example page and persist its container start count."""

import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


APP_VERSION = os.environ["APP_VERSION"]
DATA_DIR = Path("/data")
RUN_AS_GID = 65532
RUN_AS_UID = 65532
WEB_ROOT = Path("/tmp/www")


def increment_start_count() -> int:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    count_path = DATA_DIR / "start-count"
    try:
        count = int(count_path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        count = 0
    next_count = count + 1
    temporary_path = count_path.with_suffix(".new")
    temporary_path.write_text(f"{next_count}\n", encoding="utf-8")
    temporary_path.replace(count_path)
    return next_count


def render_page(start_count: int) -> None:
    template = Path("/app/index.html").read_text(encoding="utf-8")
    page = template.replace("@APP_VERSION@", APP_VERSION).replace(
        "@START_COUNT@", str(start_count)
    )
    WEB_ROOT.mkdir(parents=True, exist_ok=True)
    (WEB_ROOT / "index.html").write_text(page, encoding="utf-8")


def drop_privileges() -> None:
    os.setgroups([])
    os.setgid(RUN_AS_GID)
    os.setuid(RUN_AS_UID)


def main() -> None:
    render_page(increment_start_count())
    os.chdir(WEB_ROOT)
    drop_privileges()
    ThreadingHTTPServer(("0.0.0.0", 8080), SimpleHTTPRequestHandler).serve_forever()


if __name__ == "__main__":
    main()
