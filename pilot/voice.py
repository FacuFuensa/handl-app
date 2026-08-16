"""Vapi client for the pilot. Standard library only.

Places one outbound call with an inline assistant, waits for it to finish, and
flattens the result into the fields the pilot measures.

Field names and endpoints here were checked against Vapi's live OpenAPI spec
(api.vapi.ai/api-json, August 2026), not from memory. Two traps that cost a
real conversation if you get them wrong: the transcript lives at
artifact.transcript, not at the root, and the recording URL at the root is
deprecated in favour of artifact.recording.mono.combinedUrl.

Vapi was chosen over Retell for one structural reason: it accepts a complete
assistant inline on POST /call. Retell requires creating an Agent and an LLM up
front and cannot override the system prompt per call, which does not suit a
pilot where every call carries a different problem description.
"""

from __future__ import annotations

import base64
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

API_ROOT = "https://api.vapi.ai"
POLL_EVERY_S = 5
POLL_TIMEOUT_S = 900

# Overridable from .env; these are the documented defaults.
DEFAULT_MODEL = "gpt-4o"
DEFAULT_VOICE_PROVIDER = "11labs"
DEFAULT_VOICE_ID = "burt"

SETUP_HELP = """
Missing configuration. Create pilot/.env (gitignored) with:

    VAPI_API_KEY=...            # Vapi dashboard -> Settings -> API Keys (private)
    VAPI_PHONE_NUMBER_ID=...    # the number you dial FROM

Optional:

    VAPI_VOICE_ID=burt          # 11labs voice
    VAPI_MODEL=gpt-4o
    TWILIO_ACCOUNT_SID=...      # only for the SMS fallback
    TWILIO_AUTH_TOKEN=...
    TWILIO_FROM=+1305...

On the outbound number: buying one inside Vapi is the fast path, but branded
caller ID and STIR/SHAKEN attestation are handled by the carrier, so the route
that lets you fix "Spam Likely" is to set the number up in Twilio, complete the
business profile there, and import it into Vapi. Vapi's own docs do not cover
that step. Skip it and the pilot measures your caller ID, not your product.
"""


class VoiceError(RuntimeError):
    pass


# Verified against the endedReason enum in the live spec. Anything unmapped
# falls through to "other" and keeps its raw value in ended_reason, so an
# unexpected value shows up in the report instead of being miscounted.
END_REASON_TO_OUTCOME = {
    "customer-did-not-answer": "no_answer",
    "customer-busy": "no_answer",
    "silence-timed-out": "no_answer",
    "voicemail": "voicemail",
    "customer-ended-call": "other",
    "assistant-ended-call": "other",
    "assistant-said-end-call-phrase": "other",
}


def _request(method: str, path: str, api_key: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        f"{API_ROOT}{path}",
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:500]
        raise VoiceError(f"{method} {path} -> HTTP {e.code}: {detail}") from None
    except urllib.error.URLError as e:
        raise VoiceError(f"{method} {path} -> {e.reason}") from None


class VoiceClient:
    def __init__(self, env: dict[str, str]):
        self.api_key = env.get("VAPI_API_KEY", "")
        self.phone_number_id = env.get("VAPI_PHONE_NUMBER_ID", "")
        if not self.api_key or not self.phone_number_id:
            raise VoiceError(SETUP_HELP)
        self.model = env.get("VAPI_MODEL", DEFAULT_MODEL)
        self.voice_id = env.get("VAPI_VOICE_ID", DEFAULT_VOICE_ID)
        self.voice_provider = env.get("VAPI_VOICE_PROVIDER", DEFAULT_VOICE_PROVIDER)
        self.twilio = None
        if env.get("TWILIO_ACCOUNT_SID") and env.get("TWILIO_AUTH_TOKEN"):
            self.twilio = (
                env["TWILIO_ACCOUNT_SID"],
                env["TWILIO_AUTH_TOKEN"],
                env.get("TWILIO_FROM", ""),
            )

    # -- placing the call ---------------------------------------------------

    def build_assistant(
        self, first_message: str, system_prompt: str, voicemail_message: str
    ) -> dict:
        """Only fields confirmed present in the live spec.

        Templates are rendered in Python before they get here, so Vapi's own
        {{variable}} system is deliberately unused — one substitution step,
        one place for it to go wrong.
        """
        return {
            "name": "Handl pilot",
            "firstMessage": first_message,
            "model": {
                "provider": "openai",
                "model": self.model,
                "messages": [{"role": "system", "content": system_prompt}],
            },
            "voice": {"provider": self.voice_provider, "voiceId": self.voice_id},
            "transcriber": {
                "provider": "deepgram",
                "model": "nova-2",
                "language": "en",
            },
            # Without this the platform never recognises an answering machine
            # and the agent talks to a beep for its full duration.
            "voicemailDetection": {"provider": "vapi", "beepMaxAwaitSeconds": 30},
            # Set, so it leaves the message. Unset means it hangs up silently.
            "voicemailMessage": voicemail_message,
            # analysisPlan is marked deprecated in the spec — Vapi is migrating
            # to standalone structured outputs — but it still works and is the
            # least ceremony for a pilot. Revisit if it starts erroring.
            "analysisPlan": {
                "summaryPlan": {"enabled": True},
                "structuredDataPlan": {
                    "enabled": True,
                    "schema": {
                        "type": "object",
                        "properties": {
                            "booked": {
                                "type": "boolean",
                                "description": "True only if the provider agreed to a specific day and time.",
                            },
                            "booked_at": {
                                "type": "string",
                                "description": "The agreed day and time in plain words, empty if none.",
                            },
                            "reached_bot": {
                                "type": "boolean",
                                "description": "True if the answering party was itself an automated system or AI receptionist.",
                            },
                            "refused_because_ai": {
                                "type": "boolean",
                                "description": "True if they declined specifically because the caller is an AI.",
                            },
                            "needs_photos": {
                                "type": "boolean",
                                "description": "True if they asked to see photos before committing.",
                            },
                            "consented_to_recording": {
                                "type": "boolean",
                                "description": "True if they agreed when asked about recording at the start.",
                            },
                            "language": {
                                "type": "string",
                                "description": "Language the provider spoke: english or spanish.",
                            },
                            "notes": {
                                "type": "string",
                                "description": "Anything a founder should read, especially the reason it did not work.",
                            },
                        },
                        "required": ["booked"],
                    },
                },
            },
        }

    def call(
        self,
        to: str,
        first_message: str,
        system_prompt: str,
        voicemail_message: str,
    ) -> dict:
        body = {
            "phoneNumberId": self.phone_number_id,
            "customer": {"number": to},
            "assistant": self.build_assistant(
                first_message, system_prompt, voicemail_message
            ),
        }
        created = _request("POST", "/call", self.api_key, body)
        call_id = created.get("id")
        if not call_id:
            raise VoiceError(f"no call id in response: {json.dumps(created)[:300]}")

        call = self._wait(call_id)
        result = self._flatten(call)

        # agent.md promises the recording goes away if they say no. Keeping
        # that promise is not optional, and our own measurement row survives.
        if result.get("consented_to_recording") is False:
            result["recording_deleted"] = self._try_delete(call_id)
        return result

    def _wait(self, call_id: str) -> dict:
        deadline = time.time() + POLL_TIMEOUT_S
        while time.time() < deadline:
            call = _request("GET", f"/call/{call_id}", self.api_key)
            if call.get("status") in {"ended", "not-found"}:
                return call
            time.sleep(POLL_EVERY_S)
        raise VoiceError(f"call {call_id} did not end within {POLL_TIMEOUT_S}s")

    def _try_delete(self, call_id: str) -> bool:
        try:
            _request("DELETE", f"/call/{call_id}", self.api_key)
            return True
        except VoiceError as e:
            print(
                f"  ! could not delete the recording for {call_id}: {e}\n"
                f"  ! they asked not to be recorded — delete it by hand in the"
                f" Vapi dashboard before doing anything else."
            )
            return False

    # -- reading the result -------------------------------------------------

    @staticmethod
    def _flatten(call: dict) -> dict:
        ended_reason = call.get("endedReason", "")
        analysis = call.get("analysis") or {}
        structured = analysis.get("structuredData") or {}
        artifact = call.get("artifact") or {}
        recording = (artifact.get("recording") or {}).get("mono") or {}

        duration = 0
        started, ended = call.get("startedAt"), call.get("endedAt")
        if started and ended:
            try:
                t0 = datetime.fromisoformat(started.replace("Z", "+00:00"))
                t1 = datetime.fromisoformat(ended.replace("Z", "+00:00"))
                duration = int((t1 - t0).total_seconds())
            except ValueError:
                pass

        outcome = END_REASON_TO_OUTCOME.get(ended_reason, "other")
        # What the conversation produced outranks what telephony thinks
        # happened: a provider can agree to Thursday and then hang up first.
        if structured.get("booked"):
            outcome = "booked"
        elif structured.get("refused_because_ai"):
            outcome = "refused_bot"
        elif structured.get("needs_photos"):
            outcome = "needs_photos"

        return {
            "call_id": call.get("id"),
            "outcome": outcome,
            "ended_reason": ended_reason,
            "duration_s": duration,
            "cost_usd": float(call.get("cost") or 0),
            "booked_at": structured.get("booked_at", ""),
            "reached_bot": bool(structured.get("reached_bot")),
            "consented_to_recording": structured.get("consented_to_recording"),
            "language": structured.get("language", ""),
            "refusal_reason": structured.get("notes", "") if outcome != "booked" else "",
            "channel_that_worked": "call" if outcome == "booked" else "",
            "summary": analysis.get("summary", ""),
            "recording_url": recording.get("combinedUrl", ""),
            "transcript": artifact.get("transcript", ""),
            "finished_at": datetime.now(timezone.utc).isoformat(),
        }

    # -- SMS fallback -------------------------------------------------------

    def send_sms(self, to: str, body: str) -> dict:
        if not self.twilio:
            raise VoiceError("Twilio is not configured; see pilot/.env")
        sid, token, from_ = self.twilio
        data = urllib.parse.urlencode({"To": to, "From": from_, "Body": body}).encode()
        auth = base64.b64encode(f"{sid}:{token}".encode()).decode()
        req = urllib.request.Request(
            f"https://api.twilio.com/2010-04-01/Accounts/{sid}/Messages.json",
            data=data,
            method="POST",
            headers={
                "Authorization": f"Basic {auth}",
                "Content-Type": "application/x-www-form-urlencoded",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.loads(resp.read().decode() or "{}")
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")[:300]
            raise VoiceError(f"twilio sms -> HTTP {e.code}: {detail}") from None
