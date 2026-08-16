"""Pilot harness: place AI calls to book real home-service visits, and measure.

    py -3 run.py preview              # what the agent will say, per job. Free.
    py -3 run.py call --job 3 --yes   # dial one job
    py -3 run.py call --all --yes     # dial every pending job, one at a time
    py -3 run.py report               # the number the pilot exists to produce

Standard library only, so it runs on a stock Windows Python.

The prompts live in agent.md and are read from there. There is exactly one copy
of the recording-consent line, and it is the one a human reviews.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone, tzinfo
from pathlib import Path

HERE = Path(__file__).parent
AGENT_MD = HERE / "agent.md"
JOBS_CSV = HERE / "jobs.csv"
RESULTS_DIR = HERE / "results"
ENV_FILE = HERE / ".env"


class _Eastern(tzinfo):
    """US Eastern time, hand-rolled.

    Windows ships no IANA database, so zoneinfo("America/New_York") raises
    unless the tzdata package is installed. Keeping this file dependency-free
    matters more than generality: the rules below have held since 2007 and the
    only thing they gate is "is it business hours in Miami".
    """

    def utcoffset(self, dt):
        return timedelta(hours=-4 if self._is_dst(dt) else -5)

    def dst(self, dt):
        return timedelta(hours=1 if self._is_dst(dt) else 0)

    def tzname(self, dt):
        return "EDT" if self._is_dst(dt) else "EST"

    @staticmethod
    def _nth_weekday(year: int, month: int, weekday: int, n: int) -> datetime:
        d = datetime(year, month, 1)
        d += timedelta(days=(weekday - d.weekday()) % 7, weeks=n - 1)
        return d

    def _is_dst(self, dt) -> bool:
        if dt is None:
            return False
        naive = dt.replace(tzinfo=None)
        # Second Sunday in March at 02:00 → first Sunday in November at 02:00.
        start = self._nth_weekday(naive.year, 3, 6, 2) + timedelta(hours=2)
        end = self._nth_weekday(naive.year, 11, 6, 1) + timedelta(hours=2)
        return start <= naive < end


# Miami. Calling a tradesperson outside working hours is both rude and a
# useless measurement — a 9pm no-answer says nothing about the product.
TZ = _Eastern()
CALL_WINDOW = (9, 0), (17, 30)
CALL_DAYS = {0, 1, 2, 3, 4}

MAX_ATTEMPTS = 2
# A burst of short calls from a number nobody has saved is the exact pattern
# carriers score as spam. One at a time, with a gap.
GAP_BETWEEN_CALLS_S = 45

# Filled in from other columns, so they are legal in a template but must not be
# demanded of jobs.csv.
DERIVED_COLUMNS = {"problem_description_short"}

OUTCOMES = [
    "booked",
    "callback_promised",
    "refused_bot",
    "needs_photos",
    "voicemail",
    "no_answer",
    "wrong_number",
    "other",
]


# --------------------------------------------------------------------------
# config


def load_env() -> dict[str, str]:
    env = dict(os.environ)
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            env.setdefault(k.strip(), v.strip().strip('"').strip("'"))
    return env


# --------------------------------------------------------------------------
# the agent script, parsed out of agent.md so doc and code cannot drift


BLOCK_HEADINGS = {
    "first message": "first_message",
    "system prompt": "system_prompt",
    "voicemail": "voicemail",
    "sms fallback": "sms",
}


def load_script() -> dict[str, str]:
    if not AGENT_MD.exists():
        sys.exit(f"missing {AGENT_MD}")
    blocks: dict[str, str] = {}
    heading = None
    fence: list[str] | None = None
    for line in AGENT_MD.read_text(encoding="utf-8").splitlines():
        if line.startswith("#"):
            heading = line.lstrip("#").strip().lower()
            continue
        if line.startswith("```"):
            if fence is None:
                fence = []
            else:
                key = BLOCK_HEADINGS.get(heading or "")
                if key and key not in blocks:
                    blocks[key] = "\n".join(fence).strip()
                fence = None
            continue
        if fence is not None:
            fence.append(line)

    missing = set(BLOCK_HEADINGS.values()) - set(blocks)
    if missing:
        sys.exit(f"agent.md is missing a code block for: {', '.join(sorted(missing))}")
    return blocks


VAR_RE = re.compile(r"\{\{(\w+)\}\}")


def render(template: str, job: dict[str, str]) -> str:
    return VAR_RE.sub(lambda m: job.get(m.group(1), ""), template)


def render_sms(template: str, job: dict[str, str]) -> str:
    """SMS goes out as one blob; the template is only wrapped for reading."""
    return re.sub(r"\s+", " ", render(template, job)).strip()


def sms_segments(text: str) -> int:
    # Any non-GSM character (an em dash, an accent) pushes the whole message to
    # UCS-2, which nearly halves the characters per segment.
    unicode_msg = any(ord(c) > 127 for c in text)
    per = 70 if unicode_msg else 160
    if len(text) > per:
        per = 67 if unicode_msg else 153
    return max(1, -(-len(text) // per))


# --------------------------------------------------------------------------
# jobs


@dataclass
class Job:
    data: dict[str, str]
    attempts: list[dict] = field(default_factory=list)

    @property
    def id(self) -> str:
        return self.data["job_id"]

    @property
    def done(self) -> bool:
        """Booked, or the provider said no. Either way, stop dialling."""
        return any(
            a.get("outcome") in {"booked", "refused_bot", "wrong_number"}
            for a in self.attempts
        )


def normalize_phone(raw: str) -> str:
    digits = re.sub(r"\D", "", raw or "")
    if len(digits) == 10:
        return "+1" + digits
    if len(digits) == 11 and digits.startswith("1"):
        return "+" + digits
    if raw.startswith("+") and 8 <= len(digits) <= 15:
        return "+" + digits
    raise ValueError(f"cannot read {raw!r} as a phone number")


def load_jobs(script: dict[str, str]) -> list[Job]:
    if not JOBS_CSV.exists():
        sys.exit(
            f"missing {JOBS_CSV}\n"
            "Copy jobs.example.csv and fill it with REAL jobs somebody wants done.\n"
            "Read the rule in README.md before you do."
        )
    with JOBS_CSV.open(encoding="utf-8-sig", newline="") as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        sys.exit("jobs.csv has no rows")

    # Every variable the agent will speak must resolve. This check is the
    # difference between a professional call and one that says
    # "calling on behalf of {{customer_name}}" out loud to a real plumber.
    needed = set()
    for tpl in script.values():
        needed |= set(VAR_RE.findall(tpl))
    have = set(rows[0].keys()) | DERIVED_COLUMNS
    unresolved = needed - have
    if unresolved:
        sys.exit(
            "jobs.csv is missing columns the agent script needs: "
            + ", ".join(sorted(unresolved))
        )

    seen: set[str] = set()
    jobs = []
    for i, row in enumerate(rows, start=2):
        row = {k: (v or "").strip() for k, v in row.items() if k}
        jid = row.get("job_id", "")
        if not jid:
            sys.exit(f"row {i}: job_id is empty")
        if jid in seen:
            sys.exit(f"row {i}: duplicate job_id {jid}")
        seen.add(jid)
        for col in ("provider_phone", "customer_phone"):
            try:
                row[col] = normalize_phone(row[col])
            except ValueError as e:
                sys.exit(f"row {i} ({col}): {e}")
        for col in ("problem_description", "availability_windows", "provider_name"):
            if not row.get(col):
                sys.exit(f"row {i}: {col} is empty")
        # Templates put their own punctuation after this.
        row.setdefault(
            "problem_description_short",
            row["problem_description"][:160].rstrip().rstrip(".!,;"),
        )
        jobs.append(Job(row))

    for job in jobs:
        job.attempts = read_attempts(job.id)
    return jobs


# --------------------------------------------------------------------------
# results — appended immediately, so a crash never costs a measurement


def results_path() -> Path:
    RESULTS_DIR.mkdir(exist_ok=True)
    return RESULTS_DIR / "attempts.jsonl"


def read_attempts(job_id: str | None = None) -> list[dict]:
    p = results_path()
    if not p.exists():
        return []
    out = []
    for line in p.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        if job_id is None or rec.get("job_id") == job_id:
            out.append(rec)
    return out


def append_attempt(rec: dict) -> None:
    with results_path().open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(rec, ensure_ascii=False) + "\n")


# --------------------------------------------------------------------------
# guards


def within_calling_hours(now: datetime | None = None) -> tuple[bool, str]:
    now = now or datetime.now(TZ)
    if now.weekday() not in CALL_DAYS:
        return False, f"{now:%A} — weekend"
    (h1, m1), (h2, m2) = CALL_WINDOW
    start = now.replace(hour=h1, minute=m1, second=0, microsecond=0)
    end = now.replace(hour=h2, minute=m2, second=0, microsecond=0)
    if not (start <= now <= end):
        return False, f"{now:%H:%M} Miami time — outside {h1:02d}:{m1:02d}-{h2:02d}:{m2:02d}"
    return True, ""


def next_attempt_allowed(job: Job) -> tuple[bool, str]:
    if job.done:
        return False, "already resolved"
    if len(job.attempts) >= MAX_ATTEMPTS:
        return False, f"{len(job.attempts)} attempts already"
    if job.attempts:
        last = job.attempts[-1].get("started_at", "")
        try:
            when = datetime.fromisoformat(last)
        except ValueError:
            return True, ""
        # Retry in a different part of the day: the provider was under a sink,
        # not ignoring you. Looping immediately just burns the number.
        if datetime.now(TZ) - when < timedelta(hours=3):
            return False, "last attempt under 3h ago"
    return True, ""


# --------------------------------------------------------------------------
# commands


def cmd_preview(args) -> None:
    script = load_script()
    jobs = load_jobs(script)
    wanted = {j.strip() for j in (args.job or "").split(",") if j.strip()}
    shown = 0
    for job in jobs:
        if wanted and job.id not in wanted:
            continue
        shown += 1
        d = job.data
        print("=" * 72)
        print(f"JOB {job.id}  →  {d['provider_name']}  {d['provider_phone']}")
        print(f"for {d['customer_name']} · {d.get('category', '')}")
        if job.attempts:
            outs = ", ".join(a.get("outcome", "?") for a in job.attempts)
            print(f"attempts so far: {outs}")
        print("-" * 72)
        print("SPOKEN ON PICKUP:")
        print(indent(render(script["first_message"], d)))
        print()
        print("IF VOICEMAIL:")
        print(indent(render(script["voicemail"], d)))
        print()
        sms = render_sms(script["sms"], d)
        print(f"SMS FALLBACK ({len(sms)} chars, {sms_segments(sms)} segments):")
        print(indent(wrap(sms)))
        if args.full:
            print()
            print("SYSTEM PROMPT:")
            print(indent(render(script["system_prompt"], d)))
        print()
    if not shown:
        print("no matching jobs")
        return
    print("=" * 72)
    print(f"{shown} job(s). Nothing was dialled — preview is free.")
    print("Read the first message out loud once. If it sounds evasive, fix agent.md.")


def indent(text: str, pad: str = "    ") -> str:
    return "\n".join(pad + line for line in text.splitlines())


def wrap(text: str, width: int = 68) -> str:
    import textwrap

    return "\n".join(textwrap.wrap(text, width)) or text


def cmd_call(args) -> None:
    # Imported after the gates below, so a missing API key never hides the
    # "you are about to dial real people" confirmation.
    script = load_script()
    jobs = load_jobs(script)
    env = load_env()

    if args.job:
        wanted = {j.strip() for j in args.job.split(",")}
        jobs = [j for j in jobs if j.id in wanted]
        if not jobs:
            sys.exit("no job matched --job")
    elif not args.all:
        sys.exit("pass --job <id> or --all")

    ok, why = within_calling_hours()
    if not ok and not args.ignore_hours:
        sys.exit(
            f"Not calling: {why}.\n"
            "Tradespeople answer during work hours; calls outside them measure nothing.\n"
            "Override with --ignore-hours if you know what you are doing."
        )

    queue = []
    for job in jobs:
        allowed, reason = next_attempt_allowed(job)
        if allowed:
            queue.append(job)
        else:
            print(f"skip job {job.id}: {reason}")
    if not queue:
        print("nothing to dial")
        return

    print(f"\nAbout to place {len(queue)} real call(s) to real businesses:")
    for job in queue:
        print(f"  {job.id}  {job.data['provider_name']:<28} {job.data['provider_phone']}")
    print("\nEvery one of these must be a job somebody actually wants done.")
    if not args.yes:
        sys.exit("Re-run with --yes to dial.")

    from voice import VoiceClient

    client = VoiceClient(env)
    for i, job in enumerate(queue):
        if i:
            time.sleep(GAP_BETWEEN_CALLS_S)
        place_one(client, job, script)

    print("\nDone. `py -3 run.py report` for the numbers.")


def place_one(client, job: Job, script: dict[str, str]) -> None:
    from voice import VoiceError

    d = job.data
    # A booking that arrived by text is still a booking, and which channel got
    # it is one of the questions the pilot exists to answer.
    started = datetime.now(TZ)
    print(f"\n[{started:%H:%M}] job {job.id} → {d['provider_name']} ...", flush=True)

    rec = {
        "job_id": job.id,
        "attempt": len(job.attempts) + 1,
        "provider_name": d["provider_name"],
        "started_at": started.isoformat(),
    }
    try:
        result = client.call(
            to=d["provider_phone"],
            first_message=render(script["first_message"], d),
            system_prompt=render(script["system_prompt"], d),
            voicemail_message=render(script["voicemail"], d),
        )
    except VoiceError as e:
        rec.update(outcome="other", error=str(e))
        append_attempt(rec)
        job.attempts.append(rec)
        print(f"  failed: {e}")
        return

    rec.update(result)

    # Nobody picked up. This is where most of these recover: providers are
    # under a sink, not ignoring you, and they answer texts.
    if rec.get("outcome") in {"no_answer", "voicemail"} and client.twilio:
        sms = render_sms(script["sms"], d)
        try:
            client.send_sms(d["provider_phone"], sms)
            rec["sms_sent"] = True
            print(f"  sms sent ({sms_segments(sms)} segments)")
        except VoiceError as e:
            rec["sms_sent"] = False
            rec["sms_error"] = str(e)
            print(f"  sms failed: {e}")

    append_attempt(rec)
    job.attempts.append(rec)
    print(
        f"  {rec.get('outcome', '?')}"
        f" · {rec.get('duration_s', 0)}s"
        f" · ${rec.get('cost_usd', 0):.3f}"
    )
    if rec.get("outcome") == "booked" and rec.get("booked_at"):
        print(f"  -> {rec['booked_at']}")
    if rec.get("consented_to_recording") is False:
        state = "deleted" if rec.get("recording_deleted") else "STILL THERE"
        print(f"  they declined recording; recording {state}")


def cmd_report(args) -> None:
    script = load_script()
    jobs = load_jobs(script)
    attempts = read_attempts()
    if not attempts:
        print("No calls placed yet.")
        return

    by_job: dict[str, list[dict]] = {}
    for a in attempts:
        by_job.setdefault(a["job_id"], []).append(a)

    attempted = len(by_job)
    booked = [j for j, a in by_job.items() if any(x.get("outcome") == "booked" for x in a)]
    answered = [
        j for j, a in by_job.items()
        if any(x.get("outcome") not in {"no_answer", "voicemail", None} for x in a)
    ]
    total_cost = sum(a.get("cost_usd", 0) or 0 for a in attempts)

    print("=" * 60)
    print("PILOT RESULT")
    print("=" * 60)
    print(f"jobs attempted        {attempted}")
    print(f"reached a person/bot  {len(answered)}  ({pct(len(answered), attempted)})")
    print(f"BOOKED                {len(booked)}  ({pct(len(booked), attempted)})")
    print(f"calls placed          {len(attempts)}")
    print(f"total spend           ${total_cost:.2f}")
    if booked:
        print(f"cost per booking      ${total_cost / len(booked):.2f}")
    print()

    counts: dict[str, int] = {}
    for a in attempts:
        counts[a.get("outcome", "?")] = counts.get(a.get("outcome", "?"), 0) + 1
    print("outcomes by call")
    for name in OUTCOMES + ["?"]:
        if counts.get(name):
            print(f"  {name:<20} {counts[name]}")

    channels: dict[str, int] = {}
    for a in attempts:
        if a.get("outcome") == "booked":
            ch = a.get("channel_that_worked", "call")
            channels[ch] = channels.get(ch, 0) + 1
    if channels:
        print("\nbookings by channel")
        for ch, n in sorted(channels.items(), key=lambda x: -x[1]):
            print(f"  {ch:<20} {n}")

    refusals = [a.get("refusal_reason") for a in attempts if a.get("refusal_reason")]
    if refusals:
        print("\nwhat they said when it did not work")
        for r in refusals:
            print(f"  · {r}")

    if attempted < 8:
        print(f"\n{attempted} jobs is too few to conclude anything. Keep going.")
    elif booked and len(booked) / attempted >= 0.5:
        print("\nAbove half. The product works — price it and build it.")
    elif booked and len(booked) / attempted >= 0.25:
        print("\nWorks, with the fallback carrying weight. Check bookings by channel:")
        print("if SMS is doing the work, this is not really a calling product.")
    else:
        print("\nRead every refusal above before concluding. The usual causes are")
        print("fixable: spam labelling, an evasive script, or the wrong hour.")


def pct(n: int, d: int) -> str:
    return f"{100 * n / d:.0f}%" if d else "—"


def main() -> None:
    # The Windows console defaults to cp1252 and dies on a plain arrow.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass

    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="cmd", required=True)

    pv = sub.add_parser("preview", help="print what the agent will say. free.")
    pv.add_argument("--job", help="comma-separated job ids")
    pv.add_argument("--full", action="store_true", help="include the system prompt")
    pv.set_defaults(func=cmd_preview)

    c = sub.add_parser("call", help="place real calls")
    c.add_argument("--job", help="comma-separated job ids")
    c.add_argument("--all", action="store_true")
    c.add_argument("--yes", action="store_true", help="required to actually dial")
    c.add_argument("--ignore-hours", action="store_true")
    c.set_defaults(func=cmd_call)

    r = sub.add_parser("report", help="the number the pilot exists to produce")
    r.set_defaults(func=cmd_report)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
