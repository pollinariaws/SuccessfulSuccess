"""Lambda entry point of the report builder: an SQS message, the schedule, or a direct call."""

import json
import logging
import os

from app.reports.weekly import build_weekly_report, previous_week

log = logging.getLogger()
log.setLevel(logging.INFO)


def _requests(event):
    """Yield (trigger, payload) for every report request in the event."""
    if "Records" in event:  # SQS: the payload is the message body
        for record in event["Records"]:
            body = json.loads(record["body"])
            yield body.get("source") or "sqs", body
    else:  # direct invocation
        yield event.get("source") or "direct", event


def handler(event, context):
    import boto3

    s3 = boto3.client("s3")
    bucket = os.environ["REPORTS_BUCKET"]
    for trigger, payload in _requests(event):
        week = payload.get("week") or previous_week()
        log.info("report-builder triggered trigger=%s week=%s", trigger, week)
        body = build_weekly_report(week)
        key = f"reports/{week}.csv"
        s3.put_object(Bucket=bucket, Key=key, Body=body, ContentType="text/csv")
        log.info("report-builder saved key=%s bytes=%d", key, len(body))
    return {"status": "ok"}
