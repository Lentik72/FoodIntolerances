# Product direction and architecture decisions

**Last settled:** 2026-08-27

This is the document the round specs point at. It holds the decisions that span rounds — what the
product is for, what order it gets built, and the constraints every spec inherits. Individual specs
under `docs/superpowers/specs/` scope a single round and should **reference** this rather than
restating it, so the reasoning lives in one place and cannot drift between documents.

---

## What the app is for

Three goals, and they are **three different measurements** — not one engine with a setting.

**1. Chronic and long-lasting conditions.** Psoriasis, endometriosis, long COVID. The symptom is
always present; the question is how bad and what moves it. Needs a daily severity rating and an
estimand expressed as a difference in the person's own severity — "on magnesium days your severity
averages 1.8 lower", not "2.3× the rate". *Probably the majority of users*, on the design partner's
account. **Does not exist yet.**

**2. Episodic problems.** Migraine, food reactions. Did it happen, how often, after what. Occurrence
rates and ratios over day-level lags. **This is what the engine does today** — meaning it was built
for the secondary case.

**3. Slow, goal-directed change.** Weight, cholesterol, blood pressure. Moves over weeks and months,
tied to a sustained regimen rather than a Tuesday, measured by a scale or a lab. Day-level
co-occurrence is meaningless here; it is a before/during/after comparison. **Does not exist yet.**

## Round sequence

1. **1b — health trajectories and profile.** Descriptive trends over device-recorded history. Needs
   no symptom data at all, which is why it goes first: it gives the practice something real on day
   one while everything else accumulates.
2. **1a — daily check-in and recorded observability.** Ongoing conditions, a daily severity rating,
   and the engine change that makes a silent day mean *unknown* rather than *no symptom*.
3. **2 — the continuous estimand.** Severity differences, wired into protocols, so "did this peptide
   help" has an answer.
4. **The doctor report.** The artifact the practice actually consumes.
5. **Protocol import and export.** Portable documents in both directions.
6. **Backend and clinician surface.** Only after the practice has used the earlier rounds.

Later, unscheduled: episodes and resolution follow-ups, labs, slow outcomes, blood pressure done
properly, sleep quality beyond duration.

## The practice relationship

A functional-medicine and peptide clinic. **A design partner now; possibly a customer later**, and
the product may be sold to other practices.

They want two things: to hand protocols to patients, and to see how their patients are doing. The
first is a file format. The second is the backend.

**Their surface does not have to be an app.** Desktop/web is the likely shape, which simplifies
matters — the backend serves a browser, the iOS app barely changes, and the export document format
becomes the contract between them. It also avoids a second App Store review cycle.

**Deliberately deferred: the backend, until the practice has used the on-device version.** Not
because it is wrong — it is where this is going — but because "see how patients are doing", designed
before watching them work, will be designed wrong in its specifics. The clunky version (patient
shares a report) is already useful, and waiting costs nothing.

## Standing constraints

**On-device is the default and stays the default.** No account, no backend, no sync until the round
that adds them. A patient may choose to share; nothing leaves the device otherwise, and the app must
never present sharing as the expected path.

**Practice linkage must remain optional.** An unlinked app is fully usable. This keeps the default
path permanently outside HIPAA and keeps the consumer product viable independent of the B2B motion.

**Consent is per-share, revocable, and visible.** The patient can see exactly what left the device.

**Nothing claims a cause it cannot support.** The engine's observational ceiling, the tentative
phrasing, the contested tiers and "this doesn't rule an effect out" are one commitment, not four
features. Anything new inherits it.

**Reported history is not evidence.** "I've had this about three years" belongs in a report; it is
not three years of observation and the engine must never treat it as such.

## Where HIPAA starts, and where it does not

**It does not apply today.** The patient's own data on their own device is not PHI in the regulated
sense — the patient is not a covered entity. Consumer health apps fall under the FTC's Health Breach
Notification Rule instead, which requires disclosure of what is shared but is a far smaller burden.

**It begins the moment data is stored or transmitted on behalf of the practice** — i.e. at the
backend. At that point: a BAA with each practice, encryption in transit and at rest, access controls,
audit logging, breach notification, and a retention and deletion policy. That shapes the schema, the
auth model, and the company structure. It is not a feature to bolt on.

The useful consequence is that the line is crisp and everything before it is free.

### What to do now so the backend is not a rewrite

- **One documented, versioned export chokepoint**, with a consent record attached. Everything that
  leaves the device goes through it. Three ad-hoc share paths means auditing three later.
- **Pseudonymous subject identity in documents** — a practice identifier and a patient identifier,
  never a name and date of birth embedded in every payload. Also what stops a second practice from
  being a reshape.
- **Deletion that is real at the boundary**, even though on-device uses soft deletes because they
  are sync-friendly.
- **Protocols and reports as versioned documents, lossless in both directions.** The same format
  that carries practice → patient today is the sync payload later.

**Do not build accounts now.** UUID primary keys, soft deletes, dedup keys, timezone-stamped events
and a working migration story are already in place — that is most of what a sync engine needs.
Adding an owner column later is a routine migration in this repo. Accounts built now would be
scaffolding to throw away.

## Considered and rejected

**A shared cross-user protocol database ranking "what works".** Pooled efficacy from uncontrolled,
self-selected, unblinded data, with survivorship bias as its dominant signal — forty people try a
protocol, twenty-five quit and never report, fifteen report improvement, and the app says "88% found
this helped". That is how supplement marketing works and it is the opposite of this app's epistemics.
With unapproved peptides and a named medical practice attached, it is also a real regulatory and
liability exposure.

**The defensible version** is a practice auditing *its own cohort* under consent — clinical audit,
not a public claim. Until then, **"what works" means what works for you.**

## Compliance-relevant facts about the current codebase

**The dependency position is clean:** GRDB, ZIPFoundation, SwiftAA. No analytics, no crash reporter,
nothing that could quietly capture health content. Worth protecting deliberately — the usual
compliance problem is discovering a crash SDK has been uploading symptom names for a year.

**The legacy AI path must be compiled out of Release.** `CloudAIService` builds prompts containing
symptoms and known triggers and posts them to a third-party LLM under the user's own key. It is
currently *unreachable* in Release — `MainTabView` appears only in a `PreviewProvider` and one
`#if DEBUG` block in `HealthTabView` — but the code still ships in the binary.

Wrap `CloudAIService`, `PersonalAIAssistant`, `Views/AI/` and the `LogSymptomView` call site in
`#if DEBUG`. Three reasons, the third being the strongest: App Store review and any future BAA audit
become a one-line answer rather than an argument about reachability; a binary containing a
symptom-posting network path is a liability even when unreachable, because reachability is one
careless `NavigationLink` away; and **the compiler becomes the guard** — re-exposing it from a
Release-compiled path breaks the build, which needs no test and cannot rot, in a repo with no CI.

A consumer LLM endpoint will not sign a BAA on its default tier, so this path can never handle
practice data.

**Everything else that leaves the device** is weather and air-quality lookups, which send coordinates
rather than health content, and are covered by the first-run location screen.
