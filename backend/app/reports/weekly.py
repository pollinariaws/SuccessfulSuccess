"""Weekly meetings report: one ISO week in, one CSV out. No AWS in here."""

import asyncio
import csv
import io
import os
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine
from sqlalchemy.pool import NullPool

TOP_N = 5

SUMMARY = text("""
    SELECT count(*) AS meetings,
           coalesce(sum(extract(epoch FROM (ends_at - starts_at))) / 3600.0, 0) AS hours
    FROM meetings
    WHERE starts_at >= :start AND starts_at < :end
""")

LONGEST = text("""
    SELECT m.name, m.starts_at,
           extract(epoch FROM (m.ends_at - m.starts_at)) / 3600.0 AS hours,
           (SELECT count(*) FROM participants p WHERE p.meeting_id = m.id) AS participants
    FROM meetings m
    WHERE m.starts_at >= :start AND m.starts_at < :end
    ORDER BY hours DESC, m.starts_at
    LIMIT :n
""")


def _tz() -> ZoneInfo:
    return ZoneInfo(os.environ.get("APP_TIMEZONE", "Europe/Kyiv"))


def previous_week(today: date | None = None) -> str:
    """ISO label (e.g. "2026-W40") of the week before `today`."""
    today = today or datetime.now(_tz()).date()
    year, week, _ = (today - timedelta(days=7)).isocalendar()
    return f"{year}-W{week:02d}"


def week_bounds(week: str) -> tuple[datetime, datetime]:
    """Monday 00:00 (inclusive) to next Monday 00:00 (exclusive), in the app's timezone."""
    monday = datetime.strptime(f"{week}-1", "%G-W%V-%u").date()
    start = datetime.combine(monday, time.min, tzinfo=_tz())
    return start, start + timedelta(days=7)


async def _collect(week: str):
    start, end = week_bounds(week)
    prev_start = start - timedelta(days=7)
    # A throwaway engine without a pool: each call owns its connection, so a warm
    # Lambda never reuses one that is tied to an event loop that already closed.
    engine = create_async_engine(os.environ["DATABASE_URL"], poolclass=NullPool)
    try:
        async with engine.connect() as conn:
            this = (await conn.execute(SUMMARY, {"start": start, "end": end})).one()
            prev = (await conn.execute(SUMMARY, {"start": prev_start, "end": start})).one()
            longest = (await conn.execute(LONGEST, {"start": start, "end": end, "n": TOP_N})).all()
    finally:
        await engine.dispose()
    return this, prev, longest


def _safe(value: str) -> str:
    """Keep a spreadsheet from running a meeting title as a formula."""
    return "'" + value if value[:1] in ("=", "+", "-", "@") else value


def build_weekly_report(week: str) -> bytes:
    """Query the meetings of one ISO week (e.g. "2026-W40") and return the CSV."""
    this, prev, longest = asyncio.run(_collect(week))
    this_hours, prev_hours = float(this.hours), float(prev.hours)

    out = io.StringIO()
    writer = csv.writer(out)
    writer.writerow(["section", "label", "meetings", "hours", "start", "participants"])
    writer.writerow(["summary", week, this.meetings, f"{this_hours:.2f}", "", ""])
    writer.writerow(["summary", "previous week", prev.meetings, f"{prev_hours:.2f}", "", ""])
    writer.writerow(
        [
            "summary",
            "change",
            this.meetings - prev.meetings,
            f"{this_hours - prev_hours:+.2f}",
            "",
            "",
        ]
    )
    for row in longest:
        started = row.starts_at.astimezone(_tz()).strftime("%Y-%m-%d %H:%M")
        writer.writerow(
            ["longest", _safe(row.name), "", f"{float(row.hours):.2f}", started, row.participants]
        )
    # utf-8-sig: Excel then opens Ukrainian titles correctly.
    return out.getvalue().encode("utf-8-sig")
