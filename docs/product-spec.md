# Product Spec: Single-Input Capture Stream (working name: text-me)

Status: Draft / pre-validation
Last updated: 2026-11-09

## 1. Problem

Many people capture thoughts by texting themselves (iMessage "message yourself", WhatsApp self-chat, Telegram Saved Messages) instead of using Notes, Reminders, or a to-do app. The observed behavior: pull out phone, open Messages, type, send. No titles, no folders, no lists.

What the self-text pattern gets right:

- **No filing decision.** Nothing asks "which list?" or "what's the title?"
- **"Send" is closure.** The thought is captured and done.
- **Habit and reach.** Messages is already opened dozens of times a day; your own contact sits in the share sheet's top row.
- **Mixed content is fine.** Tasks, links, ideas, and notes coexist in one chronological stream.
- **Sync for free.** It shows up on every Apple device.

What it gets wrong:

- **Nothing resurfaces.** A deadline typed into a thread never reminds you.
- **Retrieval is poor.** Scrolling a long thread to find one item is painful. *(Assumed, not yet validated — see §10.)*
- **No completion state.** To-dos can't be checked off, so done and not-done look identical.

## 2. Product thesis

Keep the capture behavior exactly as frictionless as a self-text, then add what the thread can't do: automatic classification into overlapping views, and proactive resurfacing. **The user never organizes.** The app does not offer folders, lists, projects, or manual categories.

## 3. Design principles

1. **One input.** A single chat-style composer. The app launches with the keyboard up.
2. **The stream is the source of truth.** Every capture appears in a chronological timeline, verbatim. AI-derived views are *lenses* over the stream, never destinations items move into. Nothing is ever hidden because of a classification.
3. **No user organization.** No folders, lists, tags-as-filing, or sort options. The only user-applied metadata are *corrections* (fixing a wrong classification) and *completion* (checking off a to-do).
4. **Capture never waits on AI.** The raw item is saved instantly; classification happens asynchronously.
5. **Private by default.** All processing on-device. No backend operated by us. Sync via the user's own iCloud.
6. **The app comes to you.** Resurfacing (deadline reminders, digests) is a core feature, not an add-on.

## 4. Target user

**Market:** anyone who wants a low-friction way to capture thoughts and get them back later: not losing them, finding them, being reminded of them, using them.

**Launch segment:** people who **already have a capture workaround**, which shows they have the need:
- texting or messaging themselves (iMessage, WhatsApp "message yourself", Telegram Saved Messages)
- emailing themselves
- keeping one long running note they rarely revisit
- screenshotting things "to deal with later"

The segment is defined by behavior, not age. These people have shown they will capture; what they lack is retrieval and resurfacing. They won't invest time organizing a productivity app.

**Explicitly not targeting:** GTD and power users who enjoy organizing. They're well served by Things, Todoist, Drafts, Obsidian, etc., and the no-organization principle will frustrate them.

**Positioning (working):** App Store subtitle "Notes to self, sorted for you" (29 chars; names the existing habit plus the value, and carries search keywords). Marketing line candidates: "Jot it now. Find it later." / "Save anything. Lose nothing." See [`naming.md`](naming.md).

## 5. Core experience

### 5.1 Capture

| Surface | Behavior | v1? |
|---|---|---|
| App launch | Opens to stream with composer focused, keyboard up | Yes |
| Share extension | Save URL/text/image from any app; queued raw, classified later in the main app | Yes |
| App Intent | "Add to [app]" via Siri, Shortcuts, Action button, Control Center control | Yes |
| Lock Screen / Home Screen widget | Tap to open directly into composer | Yes (cheap) |
| Apple Watch | Dictation capture | No |
| Mac / iPad app | Stream + capture via CloudKit sync | No |

Composer accepts text, pasted links, and (stretch) photos. One send = one stream entry.

### 5.2 Stream

- Chronological timeline, newest at the bottom (chat convention), styled like a message thread.
- Each entry shows the raw content, timestamp, and small inferred-tag indicators.
- Links render with a preview (title, favicon, image via `LPMetadataProvider`).
- To-dos show a checkbox inline.
- Detected deadlines show a subtle date chip.

### 5.3 Filters

A row of chips across the top: **All · To-dos · Links · Notes**. (A fourth "Ideas" chip is an open question — see §11; Notes vs. Ideas may not be a distinction users or the model can make reliably.)

- Tags are **multi-label**: "Read this before Friday https://…" is a To-do *and* a Link *and* has a deadline. It appears under both filters.
- To-dos filter shows open items by default, with a toggle to show completed.
- Filters are views; selecting one never changes the underlying stream.

### 5.4 Correction (not organization)

Long-press an entry → "This is a to-do / This isn't a to-do / This is a link…" and "Edit deadline". Corrections:

- override model output permanently for that entry;
- are logged locally to measure classifier accuracy in the wild (on-device only; optional opt-in export for debugging is a later decision).

### 5.5 Completion

To-dos can be checked off from the stream or the To-dos filter. Completed items stay in the stream (struck through, de-emphasized) and drop out of the open To-dos view.

### 5.6 Search

v1: plain full-text search over stream content and link titles.
Later: semantic search via on-device embeddings ("that podcast idea from last month").

### 5.7 Resurfacing

| Mechanism | How | Reliability | v1? |
|---|---|---|---|
| Deadline reminders | When a deadline is detected (or corrected), schedule a `UNNotificationRequest` immediately at capture/classification time | High — no background execution required | Yes |
| Weekly digest | Fixed-time local notification ("Your week: 4 open to-dos, 7 unread links"). Summary content computed at last foreground / background refresh, or generated on open | Notification: high. Precomputed content: best-effort | Yes |
| Smart resurfacing | "You saved this idea 3 weeks ago", stale-link nudges, daily morning brief | Depends on background execution | No |

Design constraint: anything that must happen at a specific time must be a pre-scheduled local notification, not a background task (see §9, risk R4).

## 6. Classification

### 6.1 Taxonomy (v1)

Per entry, a structured result:

| Field | Type | Source |
|---|---|---|
| `isTodo` | Bool | LLM, heuristic fallback |
| `isNote` | Bool | LLM, heuristic fallback (default true if not to-do and not link-only) |
| `urls` | [URL] | `NSDataDetector` (deterministic) |
| `deadline` | Date? | `NSDataDetector` date detection + LLM disambiguation |
| `shortTitle` | String? | LLM (for long entries / digest display) |
| `isMultiItem` | Bool | LLM — flags entries like "milk, eggs, call mom" (see §11) |

Keep the taxonomy small. Every added class reduces accuracy and adds a filter chip.

### 6.2 Pipeline

```
capture → persist raw (sync) ─┐
                              ▼
                 deterministic pass (NSDataDetector: links, dates, phones, addresses)
                              ▼
          Foundation Models available? ── no ──► heuristic classifier
                              │ yes
                              ▼
          LanguageModelSession + @Generable schema (guided generation)
                              ▼
          merge: user corrections > deterministic > LLM > heuristic
                              ▼
          persist tags; schedule deadline notification if any
```

- Deterministic results always win over the LLM for links (100% precision expected).
- LLM uses guided generation (`@Generable` struct) so output is always schema-valid.
- Classification runs in the main app process, triggered on capture and on launch for any unclassified queue (e.g., share-extension items).
- Store `classifierVersion` on each entry so items can be re-classified when the prompt/model changes.

### 6.3 Device tiers

| Tier | Devices | Classification |
|---|---|---|
| A | Apple Intelligence–capable, enabled, supported language/region | Deterministic + Foundation Models |
| B | Everything else on the minimum supported iOS | Deterministic + heuristic rules (imperative verbs, "need to", "remember to", list patterns, date presence) |

Tier B must still be a usable product. Its accuracy is measured separately in the eval (see `classifier-eval-plan.md`).

## 7. Architecture

No server operated by us.

| Concern | Choice |
|---|---|
| UI | SwiftUI |
| Persistence | SwiftData (or Core Data) with CloudKit private database sync |
| Classification | `FoundationModels` framework + `NSDataDetector` + heuristic fallback |
| Link previews | `LinkPresentation` (`LPMetadataProvider`) |
| Capture surfaces | Share extension (App Group container), App Intents, WidgetKit, Control Center control |
| Notifications | `UserNotifications` local notifications |
| Background | `BGTaskScheduler` app refresh for best-effort digest precompute and classification backlog |
| Search (v1) | Predicate-based text search; later `NaturalLanguage` embeddings |

### 7.1 Data model (sketch)

```swift
@Model final class Entry {
    var id: UUID
    var createdAt: Date
    var rawText: String
    var attachments: [Attachment]       // later: images
    var source: CaptureSource           // app, shareExtension, intent, widget

    // Inferred
    var isTodo: Bool?
    var isNote: Bool?
    var urls: [URL]
    var deadline: Date?
    var shortTitle: String?
    var isMultiItem: Bool?
    var classifiedAt: Date?
    var classifierVersion: Int?
    var classifierTier: ClassifierTier? // foundationModels, heuristic

    // User-applied (corrections + completion only)
    var todoOverride: Bool?
    var deadlineOverride: Date?
    var completedAt: Date?
}
```

Effective values are computed: `override ?? inferred`.

Note on CloudKit + SwiftData: all properties must be optional or have defaults, and unique constraints aren't supported. Design the model accordingly from day one.

## 8. MVP scope

**In:**
- Stream + composer (keyboard-up launch)
- Share extension, one App Intent, one widget
- Classification: deterministic + Foundation Models + heuristic fallback
- Filter chips: All, To-dos, Links, Notes
- Long-press correction; to-do completion
- Plain text search
- Deadline local notifications; weekly digest notification
- CloudKit sync (iPhone only UI)

**Out (v1):**
- Any backend, accounts, or SMS number
- Folders, lists, manual tags, sorting
- Semantic search
- Mac/iPad/Watch apps
- Smart resurfacing beyond deadlines + weekly digest
- Splitting multi-item entries into separate items (pending §11 decision)
- Export to Reminders/Todoist

## 9. Risks

| # | Risk | Impact | Mitigation / validation |
|---|---|---|---|
| R1 | Classifier accuracy on real, messy self-notes is too low | Core thesis fails; misclassified to-dos are "lost" | Offline eval on real data before UI build (`classifier-eval-plan.md`) |
| R2 | Foundation Models device requirements exclude a meaningful share of the target audience (anyone on an older phone or with Apple Intelligence off) | Tier B becomes a large share of the experience | Measure heuristic baseline in eval; make Tier B viable; check target-user device mix during research |
| R3 | Users don't actually lose items / never retrieve | Organization adds no value for them | User research thread review (§10) |
| R4 | Background execution unreliable; Foundation Models may be unavailable or throttled in background | Digests late or empty | Time-critical surfacing uses pre-scheduled local notifications; digest generated on open as fallback; prototype background FM usage early |
| R5 | Share extension memory limits prevent on-device model use | Can't classify in extension | Queue raw items; classify in main app (already the design) |
| R6 | Users won't switch from Messages habit | No adoption regardless of quality | Invest in capture reach (share sheet, Action button, widget); measure capture frequency in pilot |
| R7 | Crowded market (Drafts, Tot, Mem, Telegram Saved Messages, Notes Quick Note) | Positioning, not tech, is the moat | Study why Drafts stayed niche; position for non-power users |
| R8 | CloudKit sync conflicts / SwiftData+CloudKit constraints | Data loss or duplicates | Conservative model design (§7.1); test multi-device early even before Mac app exists |

## 10. Pre-build user research

Goal: validate R3 and gather the eval dataset.

1. With consent, review a self-capture workaround (self-text thread, self-email folder, running note) with its owner. Start with 1 person, then 3–5 more across different ages and workaround types.
2. For the last ~100–200 entries, record: content type mix (task / link / note / idea / other), presence of deadlines, multi-item entries.
3. Ask: when did you last go back to find something? Did you find it? Ever missed something you'd written down?
4. Note device model (Apple Intelligence–capable or not).

Decision rule: proceed if (a) a meaningful share of entries are links/notes/ideas mixed with tasks, **and** (b) participants report failed or painful retrieval or missed tasks. If entries are ~90% short-lived tasks, a much simpler product is warranted.

## 11. Open questions

1. **Multi-item entries.** Does "milk, eggs, call mom" stay one entry with sub-checkboxes, or split into three stream items? Splitting breaks "the stream is verbatim"; not splitting makes the To-dos view lumpy. Eval measures how common this is.
2. **Notes vs. Ideas.** Is this a distinction users care about and the model can make? Default: single "Notes" bucket until data says otherwise.
3. **Completed to-dos in the stream** — struck through (current plan) or hidden after N days?
4. **Images.** In v1 composer or not? Classification of images adds scope.
5. **Monetization.** No server cost enables a one-time purchase; subscription harder to justify without a backend. Decide before launch, not now.
6. **Importing existing self-texts.** A one-time import of the user's Messages self-thread (Mac only, via `chat.db`) would be a strong onboarding hook but is technically fragile and privacy-sensitive.

## 12. Milestones

1. **Research + eval** (no app code): thread reviews, labeled dataset, classifier eval → go/no-go on R1–R3.
2. **Prototype:** stream, composer, Foundation Models classification, filters. Internal TestFlight with 1–5 users.
3. **Background prototype:** validate R4 (digest generation, background FM availability).
4. **MVP:** remaining in-scope items, CloudKit sync, share extension, intents.
5. **Pilot:** 2–4 weeks with target users; track capture frequency, correction rate per tag, filter usage, notification engagement.
