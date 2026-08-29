"""Check that every context snippet of the test set appears verbatim in merged.md."""

import json
import pathlib

MD = pathlib.Path("data/merged.md")
TESTSET = pathlib.Path("data/testset.json")


def main():
    md = MD.read_text(encoding="utf-8")
    testset = json.loads(TESTSET.read_text(encoding="utf-8"))

    total = 0
    missing = 0
    ambiguous = 0

    for i, entry in enumerate(testset):
        problems = []

        for snippet in entry["context"]:
            total += 1
            count = md.count(snippet)

            if count == 0:
                missing += 1
                problems.append(f"MISSING ({len(snippet)} chars): {snippet[:70]}")
            elif count > 1:
                ambiguous += 1
                problems.append(f"found {count}x ({len(snippet)} chars): {snippet[:70]}")

        if problems:
            print(f"\n[{i}] {entry['question'][:80]}")
            for problem in problems:
                print(f"    {problem}")

    print(f"\n{total} snippets: {total - missing - ambiguous} exact, "
          f"{ambiguous} ambiguous, {missing} missing")

    return 1 if missing else 0


if __name__ == "__main__":
    raise SystemExit(main())
