import json
import os
import boto3
from langchain_text_splitters import RecursiveCharacterTextSplitter

s3 = boto3.client("s3")

BUCKET = os.environ["BUCKET"]
IN_KEY = os.environ["IN_KEY"]
OUT_KEY = os.environ["OUT_KEY"]

SEPARATORS = ["\n## ", "\n\n", "\n", ". ", " ", ""]


def lambda_handler(event, context):
    chunk_size = event["chunk_size"]
    chunk_overlap = event["chunk_overlap"]

    text = s3.get_object(
        Bucket=BUCKET, Key=IN_KEY)["Body"].read().decode("utf-8")

    splitter = RecursiveCharacterTextSplitter(
        chunk_size=chunk_size,
        chunk_overlap=chunk_overlap,
        separators=SEPARATORS,
        keep_separator=True,
    )

    lines = [
        json.dumps({"id": f"chunk-{i:04d}", "text": chunk}, ensure_ascii=False)
        for i, chunk in enumerate(splitter.split_text(text))
    ]

    body = "\n".join(lines) + "\n"

    s3.put_object(Bucket=BUCKET, Key=OUT_KEY,
                  Body=body.encode("utf-8"),
                  ContentType="application/x-ndjson")

    return {"ok": True,
            "out_key": OUT_KEY,
            "chunks": len(lines),
            "chunk_size": chunk_size,
            "chunk_overlap": chunk_overlap}
