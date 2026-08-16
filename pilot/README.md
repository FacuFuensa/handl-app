# Pilot — can an AI actually book a home-service visit?

The one number nobody publishes: **what share of calls end with a visit on the
calendar.** Not answer rate (measured: ~66% for plumbing), not "AI can hold a
conversation" (obviously yes) — the completed booking. Google's *Ask for Me*
stops short of it, so there is no public benchmark to copy.

Price, margin, and whether the "if it isn't booked, you don't pay" promise is
survivable all hang off that number. Twenty calls cost under thirty dollars and
settle it.

## The rule that shapes everything

**Every call is for a job somebody actually wants done.**

Not a guideline — the design constraint. A booked visit sends a real person
driving across Miami. A plumber who blocks Thursday morning for a job that
does not exist loses a paid slot, and the first thing he learns about an AI
calling on a customer's behalf is that it wastes his day. These are the exact
providers the product depends on.

So:

- No invented jobs. If there are not twenty real ones, run fewer calls, or
  recruit people who have real pending tasks (see below).
- Never book something you intend to cancel. If a booking turns out to be
  unwanted, **call and cancel yourself, as a human, immediately.**
- The agent never haggles and never promises payment terms on the household's
  behalf.

Twenty real jobs is more than one household has. Ways to get them honestly:

1. Your own and your uncle's pending tasks — the AC service nobody scheduled,
   the leaking faucet, the annual pest inspection.
2. Friends and family in Miami with a real pending task, who agree to let the
   AI make the call. Tell them what it is. Most people find it fun.
3. Recurring maintenance that is genuinely due: AC filter service, gutter
   cleaning, alarm inspection. Real work, easy to schedule, low stakes.

A pilot of twelve honest calls beats twenty fake ones — the fake ones measure
nothing, because a provider who books a phantom job behaves differently from
one booking real work.

## This repository is public

`jobs.csv` holds real names, addresses and phone numbers. The results hold
transcripts of recorded conversations with people who agreed to be recorded by
one household's assistant — not to being published on GitHub. Both are
gitignored, along with `.env`. Only `jobs.example.csv`, with invented data, is
tracked.

Check `git status` before every commit during the pilot. The one that bit this
project before was a build log: GitHub masks secrets in the console but not in
files a job uploads, and an anon key ended up in a public artifact.

## What gets measured

One row per **attempt**, one summary per **job**. The fields that matter:

| Field | Why it exists |
|---|---|
| `answered` | The denominator for everything. Expect roughly two thirds. |
| `reached_human` vs `reached_bot` | Providers are adopting AI receptionists. Nobody has published what happens when two agents talk. |
| `outcome` | `booked` · `callback_promised` · `refused_bot` · `needs_photos` · `voicemail` · `no_answer` · `wrong_number` |
| `booked_at` | The actual date and time agreed, if any. |
| `attempts` | How many tries the job needed. Drives the real cost per booking. |
| `channel_that_worked` | `call` · `sms` · `whatsapp`. Decides how much the fallback matters. |
| `duration_s`, `cost_usd` | Real unit economics, replacing the estimate in the report. |
| `refusal_reason` | Free text. The most valuable column if the number comes back bad. |

The headline output is one fraction: **jobs booked ÷ jobs attempted**, plus the
average all-in cost of the ones that worked.

## Before the first call

Three things, in order. The first two are yours — they need an account and a
card, which is not something I can do for you.

1. **A voice platform account** (Vapi or Retell) and **an outbound US number**.
   Budget is tiny: at roughly $0.10–0.30 per connected minute and ~3 minutes a
   call, twenty calls with retries lands around $15–25.
2. **Register the number for caller ID.** Without branded caller ID and
   STIR/SHAKEN attestation, a chunk of calls show up as *Spam Likely* and never
   ring. Skip this and the pilot measures your caller ID, not your product.
3. **The disclosure script is not optional** — see `agent.md`. Florida requires
   consent from both parties to record. The opening does identification first,
   then recording consent, with a real pause.

## Reading the result

- **Above 50% booked** — the product works. Price it and build it.
- **25–50%** — works with the fallback carrying real weight. Look at
  `channel_that_worked`: if SMS is doing the job, the product is not really a
  calling product, and that changes the design.
- **Below 25%** — read every `refusal_reason` before concluding anything. The
  usual causes are fixable: spam labelling, a script that sounds evasive, or
  calling at the wrong hour. Re-run before giving up on the idea.

Whatever comes back, the honest version goes in the report — including a bad
number. A pilot that only confirms what you hoped was not a pilot.
