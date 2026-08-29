"""Check that the chunks reconstruct merged.md.

Every chunk claims a character range of the source document. Writing each
chunk back into an empty buffer at its own offset must reproduce the source,
except where the splitter stripped whitespace at a chunk boundary.
"""

import json
import pathlib

from lambdas.code.chunking import chunking

MD = pathlib.Path("data/merged.md")

CHUNK_SIZES = [400, 700, 1000, 1500]
OVERLAP_RATIO = 0.15


def check(text, chunks):
    """Return the positions where the reconstruction differs from the text."""
    buffer = [None] * len(text)

    for chunk in chunks:
        for offset, character in enumerate(chunk["text"]):
            buffer[chunk["start"] + offset] = character

    return [i for i, character in enumerate(buffer)
            if character != text[i] and not text[i].isspace()]


def main():
    text = MD.read_text(encoding="utf-8")

    failed = False

    for chunk_size in CHUNK_SIZES:
        chunk_overlap = int(chunk_size * OVERLAP_RATIO)

        raw = chunking.chunk(text, chunk_size, chunk_overlap)
        chunks = [json.loads(line) for line in raw.splitlines() if line.strip()]

        differences = check(text, chunks)

        status = "ok" if not differences else f"FAILED at {differences[:5]}"
        print(f"size {chunk_size:>5} overlap {chunk_overlap:>4}: "
              f"{len(chunks):>4} chunks, {status}")

        if differences:
            failed = True
            around = differences[0]
            print(f"    expected: {text[around - 40:around + 40]!r}")

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
