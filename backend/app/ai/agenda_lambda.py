"""Lambda entry point of the agenda parser: pasted text in, a suggested agenda out.

Runs outside the VPC (it needs Bedrock, not the database) and never writes anything:
saving goes through the normal API.
"""

import asyncio
import base64
import json
import logging
import os
import time
from datetime import date
from zoneinfo import ZoneInfo

from app.ai import agenda
from app.auth import AuthError, AuthNotConfiguredError, get_verifier

log = logging.getLogger()
log.setLevel(logging.INFO)

MAX_CHARS = 10_000


def _reply(status: int, body: dict) -> dict:
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False),
    }


def _read_body(event: dict) -> dict:
    raw = event.get("body") or ""
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8")
    return json.loads(raw)


def handler(event, context):
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    auth = headers.get("authorization", "")
    if not auth.lower().startswith("bearer "):
        return _reply(401, {"error": "Sign in to continue."})
    try:
        user = asyncio.run(get_verifier().verify(auth[7:].strip()))
    except AuthError as e:
        return _reply(401, {"error": str(e)})
    except AuthNotConfiguredError:
        return _reply(503, {"error": "Sign-in is not configured."})

    try:
        body = _read_body(event)
        text = body["text"]
        today = date.fromisoformat(body["today"])
        tz = body["tz"]
        ZoneInfo(tz)
    except (ValueError, KeyError, TypeError):
        return _reply(400, {"error": "Send JSON with text, today (YYYY-MM-DD) and tz."})
    if not isinstance(text, str) or not text.strip():
        return _reply(400, {"error": "The text is empty."})
    if len(text) > MAX_CHARS:
        return _reply(413, {"error": f"The text is longer than {MAX_CHARS} characters."})

    model = os.environ.get("PARSER_MODEL", agenda.DEFAULT_MODEL)
    started = time.monotonic()
    usage = {"input_tokens": 0, "output_tokens": 0}
    status = "ok"
    try:
        parsed, usage = agenda.parse_agenda(text, today, tz, model=model)
    except agenda.AgendaParseError as e:
        usage, status = e.usage, "no_agenda"
        result = _reply(422, {"error": str(e)})
    except agenda.AgendaBusyError as e:
        status = "busy"
        result = _reply(503, {"error": "The service is busy. Try again in a minute."})
        log.warning("agenda parse busy: %s", e)
    else:
        result = _reply(
            200,
            {
                "agenda": parsed.model_dump(mode="json"),
                "model": model,
                "prompt_version": agenda.PROMPT_VERSION,
            },
        )
    # One line per parse. The pasted text itself is never logged.
    log.info(
        json.dumps(
            {
                "event": "agenda_parsed",
                "status": status,
                "user": user.sub,
                "model": model,
                "prompt_version": agenda.PROMPT_VERSION,
                **usage,
                "latency_ms": int((time.monotonic() - started) * 1000),
                "cost_usd": agenda.cost_usd(model, usage),
            }
        )
    )
    return result
