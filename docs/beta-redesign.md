# MUST Beta Redesign

**Goal:** a beta at Mbarara University of Science and Technology that a student
can use without being taught, and that a tutor wants to keep using.

**Target:** 10–12 weeks from the start of implementation.

This document is the plan of record for the redesign. The design language is in
[`design-system.md`](./design-system.md); the product scope it changes is in
[`MVP_Brief.md`](./MVP_Brief.md).

---

## 1. Decisions locked

| Decision             | Choice                                                                   |
| -------------------- | ------------------------------------------------------------------------ |
| Visual direction     | Campus Energy                                                            |
| Session start/finish | One-tap mutual check-in; the six-digit PIN is retired                    |
| Notifications        | In-app inbox plus FCM push                                               |
| Tutor profiles       | Bio, availability, optional avatar and contact                           |
| Avatar for beta      | Generated illustrated avatars; photo upload pipeline built behind config |
| Distribution         | Signed APK, not the Play Store                                           |
| Timeline             | 10–12 weeks                                                              |

## 2. What changes for the student

- Home is a composer, not a feature directory.
- Course units are chips, not a catalogue to scan.
- Tutors are people with a year, a bio, a rating, a response time, and a quote.
- A request is one sheet, not a page.
- A session is a pass with a timeline, not a PIN form.
- The inbox tells the student what happened. They never press "check for an
  answer".
- Rating is an emoji scale and a few tags.

## 3. What changes for the tutor

- Tutor HQ surfaces requests, progress to Verified, the certificate, and recent
  reviews in one place.
- Accepting a request asks for time, length, and online/campus — the API already
  supports all three; the client currently asks only for length.
- Availability is a visible toggle.
- The certificate is a shareable pass, not a progress bar buried in a tab.

## 4. Backend changes

### 4.1 Session lifecycle

The PIN handshake is replaced by two independent check-ins.

```
Tutor confirms request → scheduled
Tutor taps I'm here     ─┐
Tutee taps I'm here     ─┴→ in_progress   (both timestamps recorded)
Tutor taps Finish       ─┐
Tutee taps Finish       ─┴→ completed     (both timestamps; accrual once)
Rating submitted        →    quality loop closes
```

New columns on `sessions`:

- `tutor_checked_in_at`
- `tutee_checked_in_at`
- `tutor_finished_at`
- `tutee_finished_at`

Endpoints:

- `POST /v1/sessions/{id}/check-in`
- `POST /v1/sessions/{id}/finish`

Removed: `reveal-pin`, `verify-pin`, `request-completion`,
`reveal-completion-pin`, `verify-completion-pin`, and the PIN columns and
counters. The migration is reversible.

**Why this is still attendance evidence:** the old code proved attendance with a
secret one party read to the other. The new code proves it with two independent
timestamps from two accounts. A tutee can no longer fabricate a session alone,
and a tutor can no longer bank hours without the student confirming. The rating
gate is unchanged.

The recorded duration is the window both were present: `started_at` is the
second check-in, `ended_at` is the **earlier** of the two finishes. Time after
one person left is not time that person can confirm, so a late finish tap cannot
extend the session. The floor is one minute, and a retried tap is idempotent.
The database enforces “live means both checked in” and “completed means both
finished”, so a future service path cannot claim attendance on one account's
word.

### 4.2 Notifications

New tables:

- `notifications` (`user_id`, `type`, `title`, `body`, `data`, `read_at`,
  `dedupe_key`, `created_at`)
- `device_tokens` (`user_id`, `token`, `platform`, `last_seen_at`)

Endpoints:

- `GET /v1/notifications`
- `GET /v1/notifications/unread-count`
- `POST /v1/notifications/{id}/read`
- `POST /v1/notifications/read-all`
- `POST /v1/notifications/devices`
- `DELETE /v1/notifications/devices/{token}`

Events now produced: request received, request accepted, request declined,
session started, session completed, session cancelled, rating received, and
promotion. Certificate-earned and session reminders are not produced yet, so they
are not in the enum: a type the client can draw but nothing raises is a dead deep
link.

Push uses Firebase Admin behind `FCM_ENABLED`, and is **deferred**: `device_tokens`
and the registration endpoints are in place, but nothing sends a push yet. The
in-app inbox is the real deliverable and works with Firebase unconfigured.
Reminders will be sent by `python -m app.cli send-session-reminders`, run by cron,
and will be idempotent through `dedupe_key`. There is no in-process scheduler.

The client is a fourth shell destination at `/notifications`. The tab badge and
the screen read the same provider, so one fetch feeds both and reading a row
clears the badge without a second request. Opening a row marks it read and pushes
the screen that answers it: the tutor's request list, matching after a decline,
the session, the rating form after a completed session, or the certificate after
a promotion. A type this build does not know is still shown with its title and
body and simply opens nothing, so an older APK does not drop a newer event.
Device-registration UI is not built yet, because nothing sends a push.

### 4.3 Tutor profile

New fields on `tutor_profiles`:

- `bio` (280 chars)
- `accepting_requests` (bool, default true)
- `avatar_url` (nullable)
- `contact_phone` (nullable, never public)

The public tutor summary adds `avatar_url`, `bio`, `accepting_requests`, and
`year_of_study`. A phone number is only returned to the two parties of a
confirmed session through `GET /v1/sessions/{id}/contact`. It is never logged,
never in a list response, and never on a public profile.

### 4.4 Reviews and rating tags

- `ratings.tags` (JSON list, fixed vocabulary).
- `GET /v1/tutors/{id}/reviews` returns recent public feedback, score, tags,
  rater initials, and date. It does not return a rater identity.
- Reported feedback is filtered.

### 4.5 Topic suggestions

`course_unit_topics` (`course_unit_id`, `label`, `sort_order`) and
`GET /v1/academics/course-units/{id}/topics`. Seeded for the six MUST pilot
units so a student taps instead of typing.

The six-unit list is **provisional** until MUST confirms the launch catalogue:
the units most likely to be asked about in years one and two, each with six or
seven student-phrased questions. Changing a list is a seed edit, not a code
change. The chips sit under the request sheet's topic field so the field does not
move while suggestions load; a failed query is said and offers a retry, and the
free-text field is always the way through.

## 5. Delivery sequence

| Week  | Phase             | Output                                                           |
| ----- | ----------------- | ---------------------------------------------------------------- |
| 1     | Foundation        | Tokens, typography, components, shell, auth restyle, design docs |
| 2     | Onboarding + Home | Faster wizard, Home composer, live session hero                  |
| 3     | Find + request    | Course chips, tutor cards, request sheet, topic chips            |
| 4     | Tutor profile     | Bio, reviews, accept-time scheduling                             |
| 5     | Notifications     | Backend, inbox, badge, FCM, deep links                           |
| 6     | Sessions          | Mutual check-in, timeline, rating with tags                      |
| 7     | Tutor HQ          | Requests, progress ring, certificate, availability               |
| 8     | Hardening         | Offline cache, error copy, analytics, crash reporting, safety    |
| 9     | Validation        | Integration tests, PostgreSQL and migration checks, performance  |
| 10    | Dry run           | 5–10 students, 5 tutors, real feedback                           |
| 11–12 | Launch            | Fixes, signed APK, content, runbook                              |

## 6. Beta launch checklist

- [ ] A signed APK installs on a clean Android device.
- [ ] The full loop works from a cold start: sign up → onboard → request →
      accept → check in → complete → rate → notification.
- [ ] A student can recover from a dropped connection on every screen.
- [ ] No secret, token, phone number, or transcript data reaches a log.
- [ ] The database builds from migrations alone and `alembic check` is clean.
- [ ] The six MUST units have topic chips and at least one eligible tutor.
- [ ] 10–15 tutors have a bio, an avatar, and a Verified or Rising badge.
- [ ] A WhatsApp support line is staffed.
- [ ] The pilot runbook names who reviews a report and within what time.
- [x] Analytics answers: how many requests, how many accepted, how many
      completed, how many rated. The counts are on the console's **Pilot funnel**
      screen and backed by `GET /v1/admin/analytics/pilot-funnel`.

## 7. Explicitly post-beta

- Availability calendars and slot booking.
- In-app chat.
- Payments.
- Leaderboards and streaks.
- Certificate PDF generation.
- Photo upload beyond the configured storage path.
- iOS distribution.

## 8. Progress

Kept current so the plan and the code do not drift apart.

- [x] **Foundation.** Tokens, palette, typography, bundled variable fonts,
      shared components, debug design preview, reference mockups, design-system
      doc.
- [x] **Home composer.** Course chips from the faculty catalogue, one question
      field, one amber action. The question travels to the results screen and
      prefills the request sheet. A **View more** chip opens the full catalogue
      as a list in a sheet, so a faculty that outgrows three chips is still
      reachable and a typed question is not lost by changing course. Home no
      longer repeats the sessions tab.
- [x] **Onboarding restyle.** Step counter, segmented progress, display
      headings, pinned action bar, tinted failure and consent surfaces.
- [x] **Find a tutor cards.** Rail and candidate cards read the tutor as a
      person — bio, year, generated avatar, rating, paused state — and the
      request sheet is on the app's buttons and inputs. Backend tutor profile
      fields are in place, and matching excludes a paused tutor with
      `not_accepting_requests`.
- [x] **Tutor profile.** Bio, public reviews and endorsed units, each section
      with its own failure and retry so a failed review query does not replace a
      readable profile. A review publishes the score, the tags and the rater's
      initials; the note each student wrote stays private to the tutor. An
      availability calendar and accept-time scheduling remain.
- [x] **Topic chips.** The request sheet reads its unit's suggestions, offers
      them under the topic field, and sends the tapped phrase as the student's
      own free text. An empty list, a failed query, and a typed topic all leave
      the form usable; the six-unit seed is provisional pending MUST's launch
      catalogue.
- [x] **Rating with tags.** The form offers the API's fixed six-value vocabulary,
      sends at most four in the order they were picked, and an empty list is a
      real submission. Unknown tags still display on a profile, so an older APK
      does not drop a newer server's vocabulary.
- [x] **Notifications backend.** `notifications` and `device_tokens`, a
      reversible migration, the inbox and device endpoints, and a producer for
      every event the enum carries. Writes share the transaction of the action
      they announce; `dedupe_key` makes a retried event at-most-once.
- [x] **Notifications client.** An inbox screen, unread badge on a fourth shell
      destination, mark-one and mark-all, paging, and a deep link per type. FCM
      push remains deferred until the in-app inbox is in the beta build.
- [x] **Sessions backend.** Mutual check-in and finish endpoints, the four
      attendance timestamps, a reversible migration, database constraints for
      both halves of the pass, and notifications when a session starts and
      completes. Minutes are the overlap both parties attended.
- [x] **Sessions client.** The check-in/finish pass replaces the PIN form: each
      party records their own arrival and departure, the card names who is
      still to tap, and finishing asks before it records a time that cannot be
      changed. The detail screen no longer offers a status transition.
- [x] **Tutor HQ.** `GET /v1/tutors/me` answers the caller's own standing,
      session and rating counters, certificate progress, and availability;
      `PATCH /v1/tutors/me` flips `accepting_requests` and returns the same shape,
      so the switch is written rather than echoed. Promotion is drawn from rated
      sessions and the average bar together — an unrated completion does not move
      the ring — and a tutor already Verified keeps the badge even while their
      current average sits below the promotion bar. The screen is a dashboard
      reached from Home: progress ring, availability toggle, the waiting-requests
      section, and a certificate summary. Inline accept/decline stays on the full
      `Waiting on you` screen; the dashboard section links there rather than
      growing a second copy of the decision. A signed-in student with no tutor
      profile is told they are not a tutor yet, not shown an error.
- [x] **Pilot funnel.** `GET /v1/admin/analytics/pilot-funnel` counts requests,
      accepted requests, completed sessions, and tutee-rated sessions for the
      operator's daily check; the console shows all four with stage-to-stage
      conversion. The stages are independent aggregates, not subtractions, so a
      cancelled session does not reappear as an open one. The screen renders an
      empty pilot as four honest zeroes, omits a stage's conversion when its
      denominator is zero rather than showing 0%, and offers a retry without raw
      exception text on failure.
- [ ] Hardening, validation, dry run, launch.
