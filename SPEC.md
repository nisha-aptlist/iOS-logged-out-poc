# Logged-out map browse: settled decisions

The behavioural contract. Every line here was decided deliberately; a change to
any of it is a product decision, not a refactor.

## Front door
- The app opens on a **launch moment** ("What does home mean to you?"), then
  goes **straight to the map**. No onboarding, no account wall, no location
  prompt before the map.
- Shipping behaviour: the launch moment plays once and advances itself.
  Prototype behaviour (`ALLoopsLaunchMoment` in Info.plist): it loops and waits
  for a tap so it can be studied. The loop is a demo affordance, not the spec.
- Map bounds are **hardcoded to San Francisco**. An anonymous first launch has no
  saved search and no profile.

## The free surface (no account)
- **Exact pins** with the floor of the rent range: `from $2.4k`.
- Clustered bubbles and individual pins coexist, decided by MapKit's own
  per-annotation collision test rather than by a zoom threshold. A building is
  a pin when it has room to be one. This was originally specified as a zoom
  threshold; the threshold constant was removed because MapKit's collision
  behaviour is the better answer, and the line is corrected here rather than
  left describing something the build does not do.
- Cluster bubbles report **rentals**, summed across their member buildings, not
  a count of buildings.
- A **listings sheet** anchored at 48%: **three buildings readable**, the rest
  rendered and **blurred**, with a signup button over them.
- Tapping a pin or a readable row opens the **listing card** at a 25% detent,
  draggable to 58%. At 25% it is a compact row with one thumbnail; the three
  photos appear at 58%. It shows the **full rent range**, bedrooms, and the
  unit count. **No bathroom count**: see stand-ins.
- The card also shows a **locked row naming what is withheld**, so the gate is
  legible before the tap.
- Chrome: place search, bedroom filters, a cycling rent ceiling, a persistent
  Sign up, and a locate control. **No map/list toggle.**

## The gate (hard)
- Fires on a **tap on the listing card** — one step past the pin, so the ask has
  a subject.
- Also fires on the list's signup button, on a blurred row, and on the header
  control.
- Withheld until signed up: **rent per unit, move-in dates, the full photo set,
  the exact address, contact**.
- Enforced in the repository signature: `gatedDetails(for:token:)` has no
  token-free overload, so a logged-out view cannot obtain `GatedDetails`.
- After signup from a building, the renter lands on **that building**, not a
  dead end.

## Location
- **Never requested at launch.** The system prompt fires only after a deliberate
  tap on the locate control.
- Order: locate tap → **our explainer** → system prompt → granted or denied.
- The explainer exists because the system prompt fires **at most once per
  install**. It converts a likely refusal into a deferral while the prompt is
  still spendable. Dismissing it must leave authorization `.notDetermined`.
- A denial must **not** immediately present the recovery sheet. The next
  deliberate tap opens it. It names the exact path: Apartment List → Location →
  While Using the App.
- **Reduced precision is a second axis**, not a state. When precision is
  withheld the UI says "Approximate location" rather than showing distances that
  are wrong by a mile.

## Non-negotiables
- One accent (International Orange) for pins and primary actions. System blue
  and the location puck are Apple's surfaces and sit outside that rule.
- Both light and dark appearances defined at the point of definition.
- Reduce Motion honoured: the launch sequence collapses to a static question.
- Blurred rows must not be readable by VoiceOver; they announce as locked.
- Every inventory count reports **units**. The free-row count is inherently a
  count of buildings (three readable rows is three tappable buildings), so it
  reports buildings **and says the word**: "3 of 30 buildings". Anything that
  says a bare number of units when it means buildings is a bug.

## Presentation layering (resolved)

Modals present **over the map**, not stacked on the listings surface. Two
layers, and the boundary is load-bearing:

- **Layer 1, persistent.** The listings/card surface is a
  `BottomSheetContainer` — a sibling in the ZStack, not a `.sheet`. It carries
  its own detents, drag, and snapping.
- **Layer 2, transient, one at a time.** Wall, detail, explainer, recovery,
  search. A single `.sheet(item:)` at ZStack level.

Why layer 1 is hand-built rather than a `.sheet`: **a permanently-presented
sheet holds the window's only presentation slot.** That is not a cosmetic
detail. It made the signup wall unreachable from all four of its entry points,
because `RootView`'s own `.sheet` and `.fullScreenCover` resolved to the same
host and were silently dropped — while every unit test passed. Presentation is
not observable from a store, which is why `UITests/PresentationTests.swift`
exists and asserts that each surface actually appears.

Two things came out better for being hand-built:

1. Background interaction is structural. The container occupies only its own
   frame, so the map above it is pannable by construction — no
   `presentationBackgroundInteraction`, no `upThrough:` threshold to get wrong.
2. The detent set can change freely. `presentationDetents(_:selection:)`
   documents nothing about a selection that is not a member of a new set, and
   swapping the set raced the corrective `onChange`. The snapping rule is now
   visible and ours. Layer 1 also gains a pull-up height, which is what a
   signed-in renter needs to read thirty unlocked rows.

Layer 1 dims behind a modal. Not only for looks: the container extends under
the home indicator and a presented sheet respects the safe area, so without the
scrim a strip of layer 1 showed through — the accent gate button bled under the
explainer.

**A trap for whoever writes more UI tests:** assert on content, never on
`app.sheets`. SwiftUI presentation hosts frequently do not surface in
XCUITest's `.sheets` collection — a probe here reported `sheets.count == 0`
while finding the explainer's buttons and eight body elements. A suite built on
`app.sheets` would have concluded the explainer does not present, the opposite
of the truth.

## Known stand-ins
- Three photographs across thirty buildings, each with a stable per-building
  crop anchor. With three photos the repetition is visible as soon as two
  adjacent rows draw the same one, which happens on the first screen. Real
  per-building photography replaces `ListingPhoto` wholesale.
- Inventory is hand-authored and plausible for the market. Nothing came from
  production.
- The launch answers are written, not collected from renter research.
- No analytics. `AuthMethod.analyticsName` exists and nothing emits an event, so
  none of the gate-placement questions this prototype exists to answer can be
  answered from it yet. Instrumentation is the next feature, not a polish item.
- No saved buildings. Every promise on the wall is "see data we are hiding",
  which frames signup as a toll; saving a building is the thing renters
  actually want an account for.
- No account surface once signed in: the header control is not interactive and
  `SessionStore.signOut()` has no caller.
- **No Dynamic Type support.** Every font is a fixed `.system(size:)` rather
  than a text style, so nothing scales for a renter who has enlarged type. This
  is the largest accessibility gap in the build; VoiceOver labels and Reduce
  Motion are handled, text size is not.

  **Do not scope this as an afternoon.** Having an `ALTypography` enum makes it
  look like a one-file change and it is not: 22 call sites go through
  `ALTypography`, and **43 raw `.system(size:)` across 10 files bypass it**
  (counted, not estimated). Honest sequencing is to route those 43 through
  `ALTypography` first, then add scaling in one place.
- Contact actions on the detail screen acknowledge and explain rather than
  sending: there is no leasing backend.
- `Listing` carries no bathroom count, so the free card deliberately does not
  claim one. It previously inferred "1 to 2 ba" from the bedroom mix, which
  would contradict the gated unit table against a real feed.
