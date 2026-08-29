import json
import os
import boto3
from langchain_text_splitters import RecursiveCharacterTextSplitter

s3 = boto3.client("s3")

SEPARATORS = ["\n## ", "\n\n", "\n", ". ", " ", ""]


def chunk(text, chunk_size, chunk_overlap):
    """Split the text and return the chunks as json lines."""
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=chunk_size,
        chunk_overlap=chunk_overlap,
        separators=SEPARATORS,
        keep_separator=True,
    )

    chunks = []
    cursor = 0

    for i, t in enumerate(splitter.split_text(text)):
        start = text.find(t, cursor)
        # The next chunk starts at most chunk_overlap characters before this
        # one ends, so searching from there keeps repeated text unambiguous.
        cursor = max(0, start + len(t) - chunk_overlap)
        chunks.append({"id": f"chunk-{i:04d}",
                       "start": start,
                       "end": start + len(t),
                       "text": t})

    return "\n".join(json.dumps(c, ensure_ascii=False) for c in chunks) + "\n"


def lambda_handler(event, context):
    bucket = os.environ["BUCKET"]
    in_key = os.environ["IN_KEY"]
    out_key = os.environ["OUT_KEY"]

    chunk_size = event["chunk_size"]
    chunk_overlap = event["chunk_overlap"]

    text = s3.get_object(
        Bucket=bucket, Key=in_key)["Body"].read().decode("utf-8")

    body = chunk(text, chunk_size, chunk_overlap)

    s3.put_object(Bucket=bucket, Key=out_key,
                  Body=body.encode("utf-8"),
                  ContentType="application/x-ndjson")

    return {"ok": True,
            "out_key": out_key,
            "chunk_size": chunk_size,
            "chunk_overlap": chunk_overlap}
