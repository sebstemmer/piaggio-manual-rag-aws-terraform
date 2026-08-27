import os
import boto3
import pypdfium2 as pdfium

s3 = boto3.client("s3")

BUCKET = os.environ["BUCKET"]
MANUAL_PDF_KEY = os.environ["MANUAL_PDF_KEY"]


def lambda_handler(event, context):
    pdf_bytes = s3.get_object(Bucket=BUCKET, Key=MANUAL_PDF_KEY)["Body"].read()
    pdf = pdfium.PdfDocument(pdf_bytes)

    total_pages = len(pdf)

    pdf.close()

    return {"total_pages": total_pages}
