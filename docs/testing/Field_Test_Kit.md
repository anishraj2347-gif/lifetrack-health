# Field test kit (weeks 8–10)

Three checks need real phones, real people and real paper reports. Each part below can be done
in one sitting. Fill in the tables, then hand this file back so the results can go into the
report (Chapter 6) and any problems can be fixed.

| Part | Report week | Time needed | You need |
|---|---|---|---|
| [A. Phones](#a-phones-week-8) | 8 | ~20 min per phone | 2–3 Android phones, the laptop, a USB cable |
| [B. Usability](#b-usability-week-9) | 9 | ~25 min per person | 5–8 people (at least 2 aged 60+), one phone with the sample family |
| [C. Real reports](#c-real-photographed-reports-week-10) | 10 | ~1 hour | 10–15 real lab reports with personal details covered |

Before any part: start the server on the laptop (`scripts/run_server_lan.sh`), check the address
with `scripts/lan_ip.sh`, and rebuild the APK (`scripts/build_apk.sh`) if the address changed.

---

## A. Phones (week 8)

Use phones that differ from the Galaxy S25 already tested: an older or low-cost phone, and one
from another maker. Use a **demo build** with the sample family.

### A1. Frame timing

With the phone on USB, from `app/`:

```
flutter drive --profile --no-dds --driver=test_driver/perf_driver.dart \
  --target=integration_test/scroll_perf_test.dart
```

Add the same `--dart-define` values the APK was built with (see `scripts/build_apk.sh`), with
`LT_DEMO_TOOLS=true`. Unlock the phone by hand within 90 seconds when the app opens, then do not
touch it: on a fresh install the test sets up the sample family itself. `flutter drive` removes the
app when it finishes, so reinstall the normal APK afterwards. Results land in
`build/<action>.frame_summary.json`; copy `average_frame_build_time_millis`,
`90th_percentile_frame_build_time_millis` and `missed_frame_build_budget_count` for each action.

### A2. Manual checks

Tick each one, or write what went wrong.

| # | Check | Phone 1 | Phone 2 | Phone 3 |
|---|---|---|---|---|
| 1 | Installs; opens behind the phone lock | | | |
| 2 | Scroll Records and Reminders: smooth, no text cut off | | | |
| 3 | Phone set to largest font and display size: every tab still readable, nothing cut off | | | |
| 4 | Scan a printed report with the camera; draft appears | | | |
| 5 | A medicine reminder fires; lock screen shows no medicine name | | | |
| 6 | Share with the doctor app; doctor sees it; End access closes it | | | |
| 7 | Doctor sends a prescription; **Check inbox** files it | | | |
| 8 | Emergency ID opens from the lock screen; QR reads with another phone's camera | | | |
| 9 | Back up; restore on a second phone with the password | | | |
| 10 | Dark mode: every screen readable | | | |
| 11 | Screenshot is blocked — check on a normal (non-demo) build, since demo builds turn screen privacy off by default | | | |

**Phones used** (model, Android version, RAM):

1.
2.
3.

### A3. Results

| Phone | Action | Avg build ms | 90th pct build ms | Missed frames |
|---|---|---|---|---|
| | | | | |

---

## B. Usability (week 9)

### B1. Before you start

- Use a phone with the **sample family** loaded (Me → Add the sample family). Never ask
  participants to enter their own health details.
- Tell each person: *"We are testing the app, not you. Think aloud as you go. You can stop at any
  time."* Ask them for verbal consent to take notes; record no names — use P1, P2, ….
- Do not help unless they are stuck for over 2 minutes; note where you helped.

### B2. Tasks

Read each task aloud exactly as written. Time it, and mark **S** (succeeded alone), **H** (needed
help) or **F** (could not finish).

| # | Task (read aloud) | What counts as success |
|---|---|---|
| 1 | "Find Anjali's latest blood sugar result. What was it, and when?" | Opens the test, reads value and date |
| 2 | "What medicines does Anjali take tonight? Mark one as taken." | Finds the night slot, swipes to tick |
| 3 | "Add a reminder for a check-up next Monday." | Custom reminder saved for that date |
| 4 | "Switch to Savitri Gupta's records." | Uses the person button or family tree |
| 5 | "The doctor wants to see your records on your phone only. Show them." | Opens Show on my phone |
| 6 | "Share your summary with the doctor on this laptop for 4 hours." | Scans code, picks Summary, 4 h, shares |
| 7 | "You've finished at the doctor. Stop them seeing your records." | Who has access now → End access |
| 8 | "Someone finds you unconscious. Show them your emergency details without unlocking." | Opens Emergency ID from the lock screen |
| 9 | "Add your blood group to the emergency card." | Me → Emergency ID, edits, saves |
| 10 | "Where could you see everyone who has looked at your records?" | Opens the access log |

### B3. After the tasks: 10 quick questions (System Usability Scale)

Ask the participant to answer each from **1 (strongly disagree)** to **5 (strongly agree)**.

1. I think that I would like to use this app frequently.
2. I found the app unnecessarily complex.
3. I thought the app was easy to use.
4. I think that I would need the support of a technical person to be able to use this app.
5. I found the various functions in this app were well integrated.
6. I thought there was too much inconsistency in this app.
7. I would imagine that most people would learn to use this app very quickly.
8. I found the app very cumbersome to use.
9. I felt very confident using the app.
10. I needed to learn a lot of things before I could get going with this app.

**Score:** for odd items take (answer − 1); for even items take (5 − answer); add them and
multiply by 2.5. The result is 0–100; about 68 is average, above 80 is good.

Then ask: *"What was the most confusing part?"* and *"What would you change first?"*

### B4. Results sheet

| P | Age group | Uses a smartphone daily? | T1 | T2 | T3 | T4 | T5 | T6 | T7 | T8 | T9 | T10 | SUS |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| P1 | | | | | | | | | | | | | |
| P2 | | | | | | | | | | | | | |
| P3 | | | | | | | | | | | | | |
| P4 | | | | | | | | | | | | | |
| P5 | | | | | | | | | | | | | |

Write each cell as `S 0:45`, `H 2:10` or `F`.

**Problems seen** (screen, what happened, how many people):

1.
2.
3.

---

## C. Real photographed reports (week 10)

### C1. Collecting reports

- Use your own reports or family members' with their permission. **Cover the name, address,
  phone number and any ID number** with paper before photographing, or use blank lab templates.
- Aim for variety: at least 3 labs, a printed table, a dot-matrix print, a crumpled page, one PDF,
  one with handwriting.

### C2. For each report

Scan it in a demo build (Records → + → scan) and, **before ticking anything**, compare the draft
with the paper:

| Report | Lab / type | Photo or PDF | Tests on paper | Tests found | Values right | Units right | Ranges right | Flagged for checking | Notes |
|---|---|---|---|---|---|---|---|---|---|
| R1 | | | | | | | | | |
| R2 | | | | | | | | | |
| R3 | | | | | | | | | |

**Most important column:** were any values **wrong but not flagged**? Note every one — that is
the failure the confirmation step exists to catch.

### C3. Summary

- Values read correctly: ___ of ___ (___ %)
- Wrong values that were flagged for checking: ___
- Wrong values that were **not** flagged: ___
- Reports that could not be read at all, and why:
