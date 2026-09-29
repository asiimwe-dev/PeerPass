# PeerPass MVP Brief

**Peer-to-Peer Academic Support Network**  
**Version:** 1.0 | **Date:** September 2026  
**Status:** Ready for development

---

## 1. Purpose of This Document

This brief defines the Minimum Viable Product (MVP) for PeerPass. It captures:

- What we will build first
- Why these features were chosen
- What is deliberately left out
- How the product will expand after the pilot

The goal is to ship a focused, trustworthy version that proves the core idea with real students, while leaving a clear path for growth that can be shown in pitch materials.

---

## 2. Problem Recap

Many university students fall behind in core course units but hesitate to ask lecturers for help. Large classes, fear of judgment, and limited access to personalised support turn small misunderstandings into retakes and academic drop-off.

Existing options (large review sessions, generic study groups, or pure self-study) often fail to address **hyper-specific** learning gaps quickly and without stigma.

PeerPass solves this by matching a struggling student with a verified peer who has already succeeded in that exact area.

---

## 3. MVP Goal

**Enable a student to request help on a specific topic, get matched with a suitable peer tutor, complete a short session, and rate the tutor — so the system can build trust and verification over time.**

If this loop works reliably in a small pilot, the foundation for a scalable academic safety net is proven.

---

## 4. Core User Flows

### Tutee

1. Creates an account (email and password) and completes the onboarding wizard:
   name, then university / faculty / year of study and consent
2. Submits a help request (course unit + specific topic)
3. Sees a short list of eligible tutors
4. Requests a session with one tutor
5. Completes the session
6. Rates the tutor

### Tutor

1. Creates an account and declares course units + grades
2. Starts as **Provisional Tutor** (if grade threshold is met)
3. Receives and accepts/declines match requests
4. Completes sessions
5. Earns ratings that can promote them to **Verified Tutor**

### System

- Filters tutors by competency and status
- Ranks eligible tutors simply
- Logs sessions
- Updates tutor verification status based on ratings

### The home screen today

The signed-in hub exists, and it is an honest empty state: it greets the student
by name and shows "Find a tutor" and "Book a session" marked **Soon**. It does
not offer a search box that returns nothing, a filter that filters an empty list,
or a card that looks tappable and is not. A student who signs in and finds
nothing works should be told plainly that the feature is not built yet, which is
both more honest and less damaging to trust than a plausible-looking stub.

---

## 5. MVP Feature Scope

### 5.1 Included (Must Have)

| Area                      | Features                                                                                                                                                                                     | Rationale                                                          |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| **Accounts & Roles**      | Sign up / login, basic profile (name, faculty, year), roles: Tutee, Provisional Tutor, Verified Tutor                                                                                        | Identity and trust require clear roles from day one                |
| **Tutor Validation**      | Self-declared course units + minimum grade (B+ / A), Provisional status on entry, filtering by competency + status                                                                           | Protects academic quality without heavy institutional integration  |
| **Matching**              | Help request (unit + topic), list of 1–3 eligible tutors, request → accept/decline flow, simple ranking (Verified > Provisional, then rating)                                                | Delivers the core value proposition                                |
| **Sessions**              | Session record on acceptance, mark as completed, basic time/note field                                                                                                                       | Creates the data needed for ratings and future incentives          |
| **Rating & Verification** | Mandatory 1–5 rating + optional short feedback after session, running average, automatic promotion (Provisional → Verified after threshold), reduced priority for low ratings, visible badge | Closes the quality loop and makes verification earned, not claimed |
| **Light Admin**           | Ability to view users/requests/sessions and manually adjust status if needed                                                                                                                 | Safety net during pilot                                            |

### 5.2 Explicitly Out of Scope for MVP

| Feature                         | Reason for Exclusion                                                              |
| ------------------------------- | --------------------------------------------------------------------------------- |
| University SSO / transcript API | High integration cost; self-declaration is sufficient for pilot                   |
| In-app chat or video            | Students already use WhatsApp/Zoom; adds complexity without proving the core loop |
| Payments / financial incentives | Incentive model starts with certificates and leadership credits                   |
| Certificate PDF generation      | Can be manual or added immediately after pilot                                    |
| Advanced AI matching            | Simple rule-based matching is clearer and more trustworthy at launch              |
| Push notifications              | Email or in-app notices are enough initially                                      |
| Multi-university / multi-campus | Focus on one institution first                                                    |
| Full analytics dashboard        | Basic logs are sufficient for early learning                                      |

---

## 6. Key Design Decisions

**1. Transcript / Portal verification (Tier 1 Proof Upload)**  
To enforce a hard gate for competency, tutors must upload a screenshot of their transcript or portal showing their grade. This replaces pure self-declaration and provides a stronger layer of trust for the pilot. The file is securely stored on the backend local file system.

**2. Provisional → Verified promotion path**  
New tutors are not hidden, but they are clearly labelled. Consistent positive ratings unlock the Verified badge. This creates a fair, transparent reputation system.

**3. Student chooses from a short list (instead of pure auto-match)**  
Giving the tutee final choice increases trust and reduces the feeling of being “assigned” a stranger.

**4. No in-app communication tools in MVP**  
The product’s job is matching and quality control. Building a full real-time chat adds too much complexity for the MVP. Instead, tutors can provide a copyable meeting link (e.g. Google Meet, Zoom) or contact info upon accepting a match. This ensures safe and immediate coordination without the overhead of maintaining an in-app messaging system.

**5. Keep the first pilot narrow**  
One (or few) high-need course units, 10–20 tutors, and the students in those units. Depth before breadth.

**6. Sign-up collects an email and a password, and nothing else**  
The name, faculty, and year are asked for in an onboarding wizard immediately
afterwards, and the account exists before the wizard runs. Registration is what
grants the session, so anything that can be collected later is better collected
later: a name is resumable — a student can leave the wizard and come back to it —
whereas an abandoned sign-up form is simply a lost student, and four fields is
enough to lose one.

**7. Onboarding is a three-step wizard**  
The wizard asks for a name, then for university, faculty, and year together,
gated on consent to store that academic context. The third step asks for the
primary course modules the student anticipates needing help with. This seeds
their profile for the matching phase.

**8. Consent is a gate, not a preference**  
The wizard will not finish without it. Under the Uganda Data Protection and
Privacy Act, grades and academic context are processed on the strength of
consent, and a preference toggle that defaults to on is not consent. The grant is
recorded once, server-side, with a timestamp, and cannot be withdrawn by sending
the field back — withdrawal has to be as express as the grant and has to be
logged, which is a separate flow.

---

## 7. Success Criteria for the MVP

The MVP will be considered successful when:

- A student can request help and receive a suitable match
- A session can be completed and rated
- Tutors can move from Provisional to Verified based on real feedback
- A small pilot can run without breaking trust or creating quality complaints
- We collect enough usage data to refine matching and incentives

Target pilot size: one priority course unit, 10–20 active tutors, and measurable session completion + rating rates.

---

## 8. Future Expansion (Beyond MVP)

This roadmap is designed to appear in pitch slides as the natural evolution of the product.

### Phase 2 – Trust & Convenience

- Official transcript / portal verification (harder gate)
- Optional portfolio links (e.g. GitHub for computing modules)
- In-app messaging or scheduled session reminders
- Automatic Teaching Assistant certificate generation
- Leadership credit export for university recognition

### Phase 3 – Scale & Institutional Integration

- University SSO
- Faculty and programme-level dashboards
- Multi-course and multi-faculty rollout
- Availability calendars and smarter matching
- Basic analytics for administrators (retake risk signals, popular topics, tutor performance)

### Phase 4 – Sustainability & Partnerships

- Corporate or institutional sponsorship of tutoring hours
- Formal partnership with academic departments
- Cross-university expansion
- Deeper LMS / LTI integration where valuable

Each phase builds directly on the proven MVP loop rather than replacing it.

---

## 9. Recommended Build Sequence

1. **Foundation** – Users, roles, profiles
2. **Competency layer** – Course units + self-declared grades + status
3. **Matching** – Help requests, filtering, ranking, accept/decline
4. **Sessions** – Create and complete session records
5. **Rating & promotion** – Scores, averages, Provisional → Verified rules

This order delivers a working end-to-end loop as early as possible.

---

## 10. Summary for Stakeholders

| Question                    | Answer                                                                            |
| --------------------------- | --------------------------------------------------------------------------------- |
| What are we building first? | A focused matching + rating system with basic tutor verification                  |
| Why this scope?             | It proves demand, quality control, and the core user experience with minimal risk |
| What do students get?       | Fast, stigma-free help from peers who have already succeeded in the same unit     |
| What do tutors get?         | A clear path to a Verified status and future certificates / credits               |
| What comes next?            | Stronger verification, certificates, institutional tools, and scale               |

---

**Document owner:** PeerPass Team  
**Related documents:** [Architecture](./architecture.md) · [Contributing](./Contribution.md) · [README](../README.md)
