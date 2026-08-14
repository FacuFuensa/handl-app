# Casita — Design Spec (2026-08-14)

## What it is

An iOS app (SwiftUI, iOS 17+) for a household to keep a shared directory of the
service providers they use — plumber, electrician, gas fitter, gardener — with
their phone numbers, so anyone in the household can find and call them in
seconds. Built for the owner's uncle and his wife: two users, older adults.
**UI language: English** (per the owner, 2026-08-14). A full Spanish
translation is parked in `docs/l10n/Localizable.es-backup.xcstrings` and can
be restored into `Casita/Localizable.xcstrings` later if wanted.

## Core flows

1. **Sign up / sign in** with email + password (display name asked at sign-up).
2. **Create a household** (gets a 6-character invite code) **or join one** by
   typing the code. The wife joins with the code the uncle shares via any app
   (ShareLink).
3. **Services list** — the home screen. Always-visible search field, category
   chips, big rows with a one-tap call button. Big bottom "Add service" button.
4. **Service detail** — giant Call button, WhatsApp button, notes, address,
   edit and delete.
5. **Household screen** — members list, invite code with share button, leave.
6. **Settings** — edit display name, sign out.

## Architecture

- `CasitaApp` → `RootRouter` → state-driven root: `loading` / `signedOut` /
  `noHousehold` / `ready`.
- `AppModel` — single `@MainActor @Observable` store.
- `Backend` protocol (async) with two implementations:
  - `SupabaseBackend` — supabase-swift **2.55.1 exact** (SPM).
  - `DemoBackend` (actor) — seeded in-memory data. Selected by `-CasitaDemo`
    launch arg, used by CI screenshots and as a clearly-bannered fallback when
    the build has no Supabase config.
- `-CasitaScreen <auth|gate|home|detail|form|household>` renders one screen
  directly with demo data — deterministic CI screenshots, inert in production
  (launch args can't be injected on device).
- Supabase URL/anon key come from Info.plist keys populated by build settings
  (`SUPABASE_URL` / `SUPABASE_ANON_KEY` passed as xcodebuild CLI args in CI —
  never committed).

## Data model (Postgres / Supabase)

- `profiles` (id = auth.users.id, display_name) — created by trigger on signup
  from metadata.
- `households` (id, name, invite_code unique 6-char no-ambiguous-chars,
  created_by).
- `household_members` (household_id, user_id → **profiles.id** so PostgREST can
  embed display names, PK both).
- `services` (id, household_id, name, category text, phone, whatsapp bool,
  notes, address, created_by, timestamps).

**RLS**: `is_member(hid)` SECURITY DEFINER helper; members read their
households/members/services and CRUD services; profiles visible to household
co-members and self. **Bootstrap via RPCs** (SECURITY DEFINER, search_path
pinned): `create_household(p_name)`, `join_household(p_code)` (case-insensitive
code), `my_household()` — all return `setof households`, avoiding the
"can't SELECT a household you don't belong to yet" RLS chicken-and-egg.
Schema allows multiple households per user; the app uses the first (v1 keeps
one-household UX).

## Design language

Warm, flat, spacious (density 3/10, motion 2/10 per design-system query).
- Terracotta primary `#BC4B26` (dark mode `#E0693D`), cream background
  `#FAF4EC` (dark `#201914`), warm ink text.
- System fonts, rounded design for headings, Dynamic Type respected everywhere
  (no fixed sizes). SF Symbols only — no emojis as icons.
- Touch targets ≥ 44pt; primary buttons 56pt; list rows ≥ 64pt.
- 14 service categories (plumber, electrician, gas, AC, gardener, painter,
  locksmith, builder, cleaning, appliances, car, health, internet, other),
  each with an SF Symbol; unknown category strings decode to `.other`.

## CI / delivery (Windows, no Mac — everything through GitHub Actions)

- **`ios-simulator.yml`** (push + manual): macos-26 runner, `brew install
  xcodegen`, `xcodegen generate`, unsigned simulator build
  (`CODE_SIGNING_ALLOWED=NO`), then boots a simulator, installs, launches each
  demo screen and captures PNGs (Spanish set + English spot-checks) as
  artifacts. Runs with **zero secrets** — this is the compile verifier and
  visual proof.
- **`ios-testflight.yml`** (manual): archive with automatic cloud signing
  (`-allowProvisioningUpdates` + ASC API key: secrets `ASC_KEY_ID`,
  `ASC_ISSUER_ID`, `ASC_KEY_P8`), `CURRENT_PROJECT_VERSION = run number`,
  export with `method: app-store-connect, destination: upload` — xcodebuild
  itself uploads to App Store Connect. Also needs `SUPABASE_URL` /
  `SUPABASE_ANON_KEY` secrets; fails fast if any secret is missing.
- Public repo `casita-app` (free unlimited Actions minutes; private macOS
  bills 10x). No secrets in git; `Casita.xcodeproj` is generated, not
  committed.

## Out of scope for v1 (noted for later)

Realtime sync (pull-to-refresh + foreground refresh instead), offline cache
file, in-app account deletion RPC (required before public App Store release,
not for TestFlight), password reset UI (Supabase hosted email works), photos
of invoices, multiple phones per service.

## Manual steps that only the account owner can do

1. Create App Store Connect API key (Admin/App Manager) → 3 GitHub secrets.
2. Create the app record in App Store Connect (bundle ID
   `com.facufuensa.casita`) — the ASC API cannot create app records.
3. Create a Supabase project, run `supabase/migrations/0001_init.sql`,
   (recommended) disable email confirmation → 2 GitHub secrets.
