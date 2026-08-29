import json
import pathlib

from lambdas.code.chunking import chunking
from lambdas.code.embed_chunks import embed_chunks
from lambdas.code.retrieval import retrieval

MD = pathlib.Path("data/merged.md")
TESTSET = pathlib.Path("data/testset.json")
CACHE = pathlib.Path("data/chunk_size_cache")

CHUNK_SIZES = [400, 700, 1000, 1500]
OVERLAP_RATIO = 0.15
K = 5


def embedded_chunks(text, chunk_size, chunk_overlap):
    """Chunk and embed, cached on disk so reruns are free."""
    cached = CACHE / f"chunks_{chunk_size}_{chunk_overlap}.jsonl"

    if not cached.exists():
        print("  embedding chunks, this takes a while ...", flush=True)
        cached.parent.mkdir(exist_ok=True)
        cached.write_text(
            embed_chunks.embed_all(
                chunking.chunk(text, chunk_size, chunk_overlap)),
            encoding="utf-8")

    return retrieval.load_chunks(cached.read_text(encoding="utf-8"))


def occurrences(text, context):
    """Character ranges of every occurrence of the context in the text."""
    ranges = []
    start = text.find(context)

    while start >= 0:
        ranges.append((start, start + len(context)))
        start = text.find(context, start + 1)

    return ranges


def covered(text, ranges, hits):
    """True if one occurrence lies inside the merged ranges of the hits.

    Chunks are stripped at their boundaries, so ranges separated by nothing
    but whitespace are treated as adjacent.
    """
    merged = []

    for start, end in sorted((h["start"], h["end"]) for h in hits):
        if merged and not text[merged[-1][1]:start].strip():
            merged[-1][1] = max(merged[-1][1], end)
        else:
            merged.append([start, end])

    return any(m_start <= start and end <= m_end
               for start, end in ranges
               for m_start, m_end in merged)


def recall(text, entry, hits):
    """Fraction of the entry's contexts covered by the retrieved chunks."""
    found = sum(covered(text, occurrences(text, context), hits)
                for context in entry["context"])
    return found / len(entry["context"])


def main():
    text = MD.read_text(encoding="utf-8")
    testset = json.loads(TESTSET.read_text(encoding="utf-8"))

    results = []

    for chunk_size in CHUNK_SIZES:
        chunk_overlap = int(chunk_size * OVERLAP_RATIO)

        print(f"processing chunk size {chunk_size} "
              f"(overlap {chunk_overlap}) ...", flush=True)

        chunks = embedded_chunks(text, chunk_size, chunk_overlap)

        print(f"  {len(chunks)} chunks, searching {len(testset)} questions ...",
              flush=True)

        ranked = [retrieval.search(entry["question"], chunks, K)
                  for entry in testset]

        recalls = [recall(text, entry, hits)
                   for entry, hits in zip(testset, ranked)]
        contexts = [sum(len(hit["text"]) for hit in hits) for hits in ranked]

        results.append((chunk_size, chunk_overlap, len(chunks),
                        sum(recalls) / len(recalls),
                        sum(contexts) / len(contexts)))

    print(f"\n{'size':>6} {'overlap':>8} {'chunks':>7} "
          f"{'recall@' + str(K):>9} {'context':>8}")

    for chunk_size, chunk_overlap, count, mean_recall, mean_context in results:
        print(f"{chunk_size:>6} {chunk_overlap:>8} {count:>7} "
              f"{mean_recall:>9.2f} {mean_context:>8.0f}")


if __name__ == "__main__":
    main()
