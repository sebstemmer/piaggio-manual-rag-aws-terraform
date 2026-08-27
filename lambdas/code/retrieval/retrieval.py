import json
import os
import traceback
import urllib.request
import boto3

s3 = boto3.client("s3")
bedrock = boto3.client("bedrock-runtime")

BUCKET = os.environ["BUCKET"]
TOKEN = os.environ["TELEGRAM_TOKEN"]
SECRET = os.environ["WEBHOOK_SECRET"]
IN_KEY = os.environ["IN_KEY"]

EMBED_MODEL = "amazon.titan-embed-text-v2:0"
CHAT_MODEL = "eu.anthropic.claude-sonnet-4-5-20250929-v1:0"
TOP_K = 5

_cache = {}


def load_chunks():
    """Load and cache the embedded chunks between warm invocations."""
    if "data" not in _cache:
        raw = s3.get_object(
            Bucket=BUCKET, Key=IN_KEY)["Body"].read().decode("utf-8")
        _cache["data"] = [json.loads(l) for l in raw.splitlines() if l.strip()]
    return _cache["data"]


def embed(text):
    resp = bedrock.invoke_model(
        modelId=EMBED_MODEL,
        body=json.dumps(
            {"inputText": text, "dimensions": 1024, "normalize": True}),
    )
    return json.loads(resp["body"].read())["embedding"]


def search(query, k=TOP_K):
    """Vectors are normalized, so the dot product is the cosine similarity."""
    q = embed(query)
    return sorted(
        load_chunks(),
        key=lambda c: sum(a * b for a, b in zip(q, c["embedding"])),
        reverse=True,
    )[:k]


def answer(query, hits):
    context = "\n\n---\n\n".join(h["text"] for h in hits)
    prompt = (
        "Beantworte die Frage ausschliesslich anhand der folgenden Auszuege "
        "aus einem Fahrzeug-Wartungshandbuch. Steht die Antwort nicht darin, "
        "sage das offen. Gib Warnhinweise mit aus, wenn sie zur Frage gehoeren. "
        "Antworte kurz und praegnant in maximal zwei Saetzen.\n\n"
        f"AUSZUEGE:\n{context}\n\nFRAGE: {query}"
    )
    resp = bedrock.invoke_model(
        modelId=CHAT_MODEL,
        body=json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 1000,
            "messages": [
                {"role": "user", "content": [{"type": "text", "text": prompt}]}
            ],
        }),
    )
    result = json.loads(resp["body"].read())
    return "".join(b["text"] for b in result["content"] if b["type"] == "text")


def send(chat_id, text):
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{TOKEN}/sendMessage",
        data=json.dumps({"chat_id": chat_id, "text": text}).encode(),
        headers={"Content-Type": "application/json"},
    )
    urllib.request.urlopen(req, timeout=10)


def lambda_handler(event, context):
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    if headers.get("x-telegram-bot-api-secret-token") != SECRET:
        return {"statusCode": 403, "body": "forbidden"}

    update = json.loads(event.get("body") or "{}")
    message = update.get("message") or {}
    text = message.get("text")
    chat_id = (message.get("chat") or {}).get("id")

    if not text or not chat_id:
        return {"statusCode": 200, "body": "ok"}

    # Always return 200 - otherwise Telegram retries and we process twice.
    try:
        send(chat_id, answer(text, search(text)))
    except Exception:
        traceback.print_exc()
        try:
            send(chat_id, "Fehler bei der Verarbeitung.")
        except Exception:
            traceback.print_exc()
    return {"statusCode": 200, "body": "ok"}
