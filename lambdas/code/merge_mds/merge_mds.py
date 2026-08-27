import os
import boto3

s3 = boto3.client("s3")

BUCKET = os.environ["BUCKET"]
IN_KEY_PREFIX = os.environ["IN_KEY_PREFIX"]
OUT_KEY = os.environ["OUT_KEY"]

EMPTY_PAGE = "[LEERE SEITE]"


def lambda_handler(event, context):
    total_pages = event["total_pages"]

    parts = []
    empty_pages = []

    for page in range(1, total_pages + 1):
        in_key = f"{IN_KEY_PREFIX}/page_{page:03d}.md"
        markdown = s3.get_object(
            Bucket=BUCKET, Key=in_key)["Body"].read().decode("utf-8").strip()

        if markdown == EMPTY_PAGE:
            empty_pages.append(page)
            continue

        parts.append(markdown)

    merged = "\n\n".join(parts)

    s3.put_object(Bucket=BUCKET, Key=OUT_KEY,
                  Body=merged.encode("utf-8"),
                  ContentType="text/markdown; charset=utf-8")

    return {"ok": True,
            "out_key": OUT_KEY,
            "total_pages": total_pages,
            "merged_pages": len(parts),
            "chars": len(merged)}
