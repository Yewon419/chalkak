"""찰칵 갤러리를 이미지까지 품은 단일 HTML로 만든다.

아티팩트의 index.html은 png를 상대 경로로 참조한다. 어디에 올리든 파일 하나로 열리게
img src를 data URI로 치환한다(Claude Artifact 같은 단일 파일 호스팅용).

    python3 scripts/inline_gallery.py <screenshots-dir> <out.html>
"""

from __future__ import annotations

import base64
import re
import sys
from pathlib import Path

IMG_SRC = re.compile(r'src="([^"]+\.png)"')


def inline(src_dir: Path) -> str:
    page = (src_dir / "index.html").read_text(encoding="utf-8")

    def swap(match: re.Match[str]) -> str:
        png = src_dir / match.group(1)
        b64 = base64.b64encode(png.read_bytes()).decode("ascii")
        return f'src="data:image/png;base64,{b64}"'

    return IMG_SRC.sub(swap, page)


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: inline_gallery.py <screenshots-dir> <out.html>", file=sys.stderr)
        return 2
    src_dir, out = Path(argv[1]), Path(argv[2])
    out.write_text(inline(src_dir), encoding="utf-8")
    print(f"{out} ({out.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
