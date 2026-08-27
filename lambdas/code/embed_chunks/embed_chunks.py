import json
import os
import boto3

s3 = boto3.client("s3")
bedrock = boto3.client("bedrock-runtime")

BUCKET = os.environ["BUCKET"]
IN_KEY = os.environ["IN_KEY"]
OUT_KEY = os.environ["OUT_KEY"]

MODEL_ID = "amazon.titan-embed-text-v2:0"
DIMENSIONS = 1024


def embed(text):
    resp = bedrock.invoke_model(
        modelId=MODEL_ID,
        body=json.dumps({
            "inputText": text,
            "dimensions": DIMENSIONS,
            "normalize": True,
        }),
    )
    return json.loads(resp["body"].read())["embedding"]


def lambda_handler(event, context):
    raw = s3.get_object(
        Bucket=BUCKET, Key=IN_KEY)["Body"].read().decode("utf-8")
    chunks = [json.loads(l) for l in raw.splitlines() if l.strip()]

    for chunk in chunks:
        chunk["embedding"] = embed(chunk["text"])

    body = "\n".join(json.dumps(c, ensure_ascii=False) for c in chunks) + "\n"
    s3.put_object(Bucket=BUCKET, Key=OUT_KEY,
                  Body=body.encode("utf-8"),
                  ContentType="application/x-ndjson")

    return {"ok": True, "out_key": OUT_KEY, "chunks": len(chunks),
            "dimensions": len(chunks[0]["embedding"]) if chunks else 0}
