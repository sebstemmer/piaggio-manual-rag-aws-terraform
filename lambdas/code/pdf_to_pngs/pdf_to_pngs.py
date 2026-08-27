import io
import os
import boto3
import pypdfium2 as pdfium

s3 = boto3.client("s3")

BUCKET = os.environ["BUCKET"]
MANUAL_PDF_KEY = os.environ["MANUAL_PDF_KEY"]
OUT_KEY_PREFIX = os.environ["OUT_KEY_PREFIX"]


def lambda_handler(event, context):
    page = event["page"]
    dpi = event.get("dpi", 200)

    pdf_bytes = s3.get_object(Bucket=BUCKET, Key=MANUAL_PDF_KEY)["Body"].read()
    pdf = pdfium.PdfDocument(pdf_bytes)

    if not 1 <= page <= len(pdf):
        raise ValueError(f"page {page} out of range (document has {len(pdf)})")

    img = pdf[page-1].render(scale=dpi / 72).to_pil()

    total_pages = len(pdf)

    pdf.close()

    buf = io.BytesIO()
    img.save(buf, format="PNG")

    out_key = f"{OUT_KEY_PREFIX}/page_{page:03d}.png"
    s3.put_object(Bucket=BUCKET, Key=out_key,
                  Body=buf.getvalue(), ContentType="image/png")

    return {"ok": True,
            "page": page,
            "out_key": out_key,
            "size": img.size,
            "total_pages": total_pages}
