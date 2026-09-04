"""찰칵 갤러리: shots.tsv + gallery.html 템플릿 -> index.html.

shoot.sh가 촬영 후 호출한다. 이미지는 상대 경로로 참조하므로 아티팩트 zip을 풀거나
정적 호스팅(GitHub Pages 등)에 그대로 올리면 열린다. 표준 라이브러리만 쓴다.
"""

from __future__ import annotations

import html
import os
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

ALIVE = "살아있음"


@dataclass(frozen=True)
class Shot:
    name: str
    mode: str
    file: str
    status: str


def read_shots(tsv: Path) -> list[Shot]:
    shots: list[Shot] = []
    for line in tsv.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        name, mode, file, status = line.split("\t")
        shots.append(Shot(name, mode, file, status))
    return shots


def card(shot: Shot) -> str:
    cls = "ok" if shot.status == ALIVE else "bad"
    name, mode, file, status = (
        html.escape(v) for v in (shot.name, shot.mode, shot.file, shot.status)
    )
    return (
        "    <figure>\n"
        f'      <button class="frame" data-cap="{name} · {mode}"><img src="{file}" alt="{name} ({mode})" loading="lazy"></button>\n'
        f'      <figcaption><span><span class="name mono">{name}</span><span class="mode">{mode}</span></span>'
        f'<span class="chip {cls}">{status}</span></figcaption>\n'
        "    </figure>"
    )


def run_link() -> tuple[str, str]:
    server = os.environ.get("GITHUB_SERVER_URL", "")
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    if server and repo and run_id:
        return f"{server}/{repo}/actions/runs/{run_id}", f"#{run_id}"
    return "#", "로컬 실행"


def render(
    template: Path, shots: list[Shot], title: str, bundle: str, device: str
) -> str:
    ok = sum(1 for s in shots if s.status == ALIVE)
    bad = len(shots) - ok
    tally = f'<span class="chip ok">살아있음 {ok}</span>'
    if bad:
        tally += f'<span class="chip bad">죽음·실행 실패 {bad}</span>'
    url, label = run_link()
    when = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    cards = (
        "\n".join(card(s) for s in shots)
        if shots
        else '    <p class="empty">찍힌 컷이 없다.</p>'
    )
    return (
        template.read_text(encoding="utf-8")
        .replace("__TITLE__", html.escape(title))
        .replace("__HEADING__", html.escape(title))
        .replace("__BUNDLE__", html.escape(bundle))
        .replace("__DEVICE__", html.escape(device))
        .replace("__RUN_URL__", html.escape(url))
        .replace("__RUN_LABEL__", html.escape(label))
        .replace("__WHEN__", when)
        .replace("__TALLY__", tally)
        .replace("__CARDS__", cards)
    )


def main(argv: list[str]) -> int:
    if len(argv) != 5:
        print(
            "usage: gallery.py <out-dir> <title> <bundle-id> <device>", file=sys.stderr
        )
        return 2
    out_dir, title, bundle, device = Path(argv[1]), argv[2], argv[3], argv[4]
    template = Path(__file__).with_name("gallery.html")
    shots = read_shots(out_dir / "shots.tsv")
    (out_dir / "index.html").write_text(
        render(template, shots, title, bundle, device), encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
