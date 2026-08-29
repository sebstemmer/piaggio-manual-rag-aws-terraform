import json
import os
import boto3

s3 = boto3.client("s3")
bedrock = boto3.client("bedrock-runtime")

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


def embed_all(raw):
    """Take chunks as json lines, return them with their embedding added."""
    chunks = [json.loads(l) for l in raw.splitlines() if l.strip()]

    for chunk in chunks:
        chunk["embedding"] = embed(chunk["text"])

    return "\n".join(json.dumps(c, ensure_ascii=False) for c in chunks) + "\n"


def lambda_handler(event, context):
    bucket = os.environ["BUCKET"]
    in_key = os.environ["IN_KEY"]
    out_key = os.environ["OUT_KEY"]

    raw = s3.get_object(
        Bucket=bucket, Key=in_key)["Body"].read().decode("utf-8")

    body = embed_all(raw)

    s3.put_object(Bucket=bucket, Key=out_key,
                  Body=body.encode("utf-8"),
                  ContentType="application/x-ndjson")

    return {"ok": True, "out_key": out_key, "dimensions": DIMENSIONS}
