import base64
import json
import logging
import os
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")
bedrock = boto3.client("bedrock-runtime")

PROMPT = """Du extrahierst eine Seite aus einem technischen Wartungshandbuch als Markdown.

LAYOUT
Die Seite ist mehrspaltig. Lies in inhaltlich logischer Reihenfolge:
ein Abschnitt setzt sich oft in der nächsten Spalte fort.

VOLLSTÄNDIGKEIT
Gib jeden Textblock der Seite aus. Überspringe nichts.
Warnkästen sind sicherheitsrelevant und müssen alle erscheinen, auch
wenn ein Kasten am Seitenanfang unvollständig beginnt.

REIHENFOLGE
Halte die Reihenfolge der Arbeitsschritte exakt ein. Ein Schritt, der
im Layout vor einem anderen steht, steht auch in der Ausgabe davor.

REGELN
- Überschriften als ## Überschrift. Jede Abschnittsüberschrift bekommt
  ##, auch wenn sie mitten auf der Seite steht.
- Warnkästen als Blockquote mit Präfix:
  > **HINWEIS:** TEXT DES KASTENS
  Setze den Kasten an die Stelle, zu der er inhaltlich gehört.
- Abbildungen als *[Abb.: kurze sachliche Beschreibung]* an der Stelle,
  auf die sie sich bezieht. Beschreibe, was gezeigt wird und wohin
  Pfeile zeigen.
- Kopf- und Fußzeilen (Kapitelname, Seitenzahl) weglassen.
- Silbentrennung am Zeilenende auflösen. Ergänzungsbindestriche wie
  "VORDERRAD- ODER HINTERRADBREMSE" beibehalten.
- Gib den Text exakt so wieder, wie er dasteht. Erfinde nichts und
  formuliere nicht um. Kannst du eine Stelle nicht sicher lesen,
  markiere sie mit [unleserlich].
- Beginnt oder endet die Seite mitten im Satz, markiere das mit [...].
- Ist die Seite leer oder enthält nur Layoutelemente ohne Inhalt, gib
  exakt [LEERE SEITE] aus und sonst nichts. Stelle keine Rückfragen und
  kommentiere die Bildqualität nicht.

AUSGABE
Nur das Markdown. Keine Vorrede, keine Codeblock-Zäune, keine Kommentare."""


BUCKET = os.environ["BUCKET"]
IN_KEY_PREFIX = os.environ["IN_KEY_PREFIX"]
OUT_KEY_PREFIX = os.environ["OUT_KEY_PREFIX"]
MAX_TOKENS = 8000


def lambda_handler(event, context):
    page = event["page"]
    in_key = f"{IN_KEY_PREFIX}/page_{page:03d}.png"
    out_key = f"{OUT_KEY_PREFIX}/page_{page:03d}.md"
    model_id = event["model_id"]

    png = s3.get_object(Bucket=BUCKET, Key=in_key)["Body"].read()

    resp = bedrock.invoke_model(
        modelId = model_id,
        body = json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": MAX_TOKENS,
            "system": PROMPT,
            "messages": [{
                "role": "user",
                "content": [
                    {"type": "image",
                     "source": {"type": "base64",
                                "media_type": "image/png",
                                "data": base64.b64encode(png).decode()}},
                    {"type": "text", "text": "Extrahiere diese Seite."},
                ],
            }],
        })
    )

    result = json.loads(resp["body"].read())
    markdown = "".join(b["text"]
                       for b in result["content"] if b["type"] == "text")
    stop_reason = result.get("stop_reason")

    if stop_reason == "max_tokens":
        logger.warning({"event": "output_truncated",
                        "page": page,
                        "out_key": out_key,
                        "model_id": model_id,
                        "max_tokens": MAX_TOKENS,
                        "usage": result.get("usage")})
        markdown += "\n\n<!-- WARNING: output truncated -->"

    s3.put_object(Bucket=BUCKET, Key=out_key,
                  Body=markdown.encode("utf-8"),
                  ContentType="text/markdown; charset=utf-8")

    return {"ok": True,
            "page": page,
            "out_key": out_key,
            "model_id": model_id,
            "stop_reason": stop_reason,
            "chars": len(markdown),
            "usage": result.get("usage")}
