"""Lambda entry point of the report mailer: an S3 upload in, an email out."""

import logging
import os
import urllib.parse
from email.message import EmailMessage

log = logging.getLogger()
log.setLevel(logging.INFO)


def handler(event, context):
    import boto3

    s3 = boto3.client("s3")
    ses = boto3.client("sesv2")
    recipients = [a.strip() for a in os.environ["MAIL_TO"].split(",") if a.strip()]
    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        log.info("report-mailer triggered trigger=s3 bucket=%s key=%s", bucket, key)

        filename = os.path.basename(key)
        week = filename.removesuffix(".csv")
        csv_bytes = s3.get_object(Bucket=bucket, Key=key)["Body"].read()

        msg = EmailMessage()
        msg["Subject"] = f"Weekly meetings report {week}"
        msg["From"] = os.environ["MAIL_FROM"]
        msg["To"] = ", ".join(recipients)
        msg.set_content(f"The meetings report for {week} is attached.")
        msg.add_attachment(csv_bytes, maintype="text", subtype="csv", filename=filename)

        ses.send_email(Content={"Raw": {"Data": msg.as_bytes()}})
        log.info("report-mailer sent key=%s to=%d recipient(s)", key, len(recipients))
    return {"status": "sent"}
