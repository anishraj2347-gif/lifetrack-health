# Changelog

Patient app (`app/`) and doctor web app (`doctor/`). Bump the version with every update:
a new feature raises the middle number, a fix raises the last; the build number (`+N`)
always goes up (Android refuses to install a lower one).

## Patient app

### 1.30.0 (10 Oct 2026)
- **Rounded top bar**: the top bar is a floating glass pill like the tab bar, and so is the header
  of every inner screen.
- **Person switcher in the top bar**: the lime avatar and first name at the top right show whose
  records are open on every tab; tap it to switch person, open the family overview or add someone.
  The avatar row above Reminders and Records is gone (more room), and so is the "Viewing …" pill
  on Share and Insights. When the records are not your own, the authority line ("you are the
  parent — declared") still shows under the title.
- Reminders' eyebrow is today's date; Records' is how many records there are.

### 1.29.0 (10 Oct 2026)
- **Insights in glass**: findings are glass cards with a slim severity bar at the edge (orange for
  "Next visit", grey for "Good to know"); only "Contact your doctor today" and "Seek care now"
  stay solid orange. Badge words are short so they no longer repeat the sentence below. The two
  counts are larger and count up from 0.
- **One round tick everywhere** (checkboxes and the access-level cards); access-level cards are
  glass with an ink outline when chosen.
- **Dark mode**: black cards are darker than the glass again, so they stand out; the colour wash
  is richer.
- Type sizes snapped to one scale (12 / 14 / 15 / 16 / 20 …); descriptions on black cards are 14.

### 1.28.0 (10 Oct 2026)
- **Branded start**: the launch screen is the page colour with the LifeTrack card-deck mark (light
  and dark, Android 12+ system splash too), then the same mark and name while records open — no
  white flash, no bare spinner. The card-deck mark replaces the heart icon in the top bar.
- **Sliding tab highlight**: one lime pill glides to the tab you pick, with a little overshoot.
  Long-press a tab to see its name large.
- **No stock Material left in the common paths**: Lucide back arrow and menu icon; "Are you sure?"
  is a glass sheet with a big confirm button (orange when it deletes) above "Keep"; sheets have a
  drag handle and 22 px corners; menus, dialogs and the date picker match the cards; text fields
  are glass with a bright rim.
- **Light/dark cross-fades** (300 ms) when changed in Me → Appearance.
- Vitals' "Add a reading" is a glossy floating pill. Emergency ID has its own ambulance icon in
  ink, so the heart is only the logo.

### 1.27.1 (10 Oct 2026)
- **Choice chips fit their label again** (since 1.20.0 they stretched to the full row, so
  "Female / Male / Prefer not to say" looked like three big buttons). Selected chips are glossy
  black with a soft shadow instead of a grey ring, and screen readers say "selected".
- Disabled buttons are grey, so a blocked "Continue" no longer looks like a second black button.
- Nothing turns lime by accident (the scan page's remove button was lime); dates on "Show on my
  phone" read "1 Oct 2026"; the "→" arrows that Poppins lacks are now "›".

### 1.27.0 (10 Oct 2026)
- **Liquid glass everywhere**: every screen sits on a soft wash of sky, lilac and peach (never a
  health colour, never lime). Cards are frosted glass with a bright rim, a sheen across the top
  and a soft shadow; black cards and buttons have a glossy finish; chips, notes and icon tiles
  match. Taps show a soft material ripple. Plain cards are see-through rather than live-blurred,
  so long lists stay smooth; the bars keep the live blur.
- Section labels are a shade darker so they stay readable over the wash.

### 1.26.0 (10 Oct 2026)
- **Glass bars**: the bottom tab bar, the top bar and the header of every inner screen are now
  frosted glass. What scrolls underneath shows through, blurred and tinted, with a thin bright
  rim and a soft sheen. The "done" card is glass too. Text on glass is checked against the worst
  case (the brightest or darkest thing that could pass behind it), so it stays readable.

### 1.25.1 (10 Oct 2026)
- Test fix only: the app-lock test scrolls to the switch, which moved under "This phone" on Me.

### 1.25.0 (10 Oct 2026)
- **Show on my phone is locked to the summary**: back, and "Give back", ask for your fingerprint,
  face or PIN first, so the doctor cannot wander into the rest of the app.
- **Erase** names the person ("Erase Aarav's profile?") and asks for the phone's own lock instead
  of typing ERASE.
- **Access log**: an export now says "password-protected" or "not encrypted", as it was made.
  Lock-screen reads say "Opened from the lock screen (not unlocked)".
- **Share**: each access has full-width "Change time" and "End access" buttons; ending asks first.
  Access levels use tick boxes (you can pick several); the medicines question explains what
  ticking does.
- **Emergency ID**: a "No known allergies" choice, shown plainly rather than as an allergy alert.
- **Times** are 12-hour everywhere (2:30 PM). Date of birth pickers open on the year.
- **Backup**: a warning to keep the password off WhatsApp, Gmail and Google Photos.
- **First screen**: "I've used LifeTrack before — restore" comes before sample records.
- **Insights**: plainer words ("Check my reports"; what turning it on does, in one sentence).
- **Me** is grouped into "Your profile" and "This phone"; the LifeTrack ID has a copy button.
- Lime is now only for "selected / now"; icon tiles on black cards are dark grey.

### 1.24.0 (10 Oct 2026)
- **Easier to read**: secondary text is 14 sp and darker (it carries most of the consent wording);
  nothing in the app is smaller than 12 sp. The main tabs and nine inner screens are tested at
  twice the phone's text size with nothing cut off.
- **Family bar**: the two round buttons now say "Family" and "Add person"; "Add person" is
  outlined so it is not mistaken for "Add record".
- **Dose**: starts at 0-0-0 and must be set before saving, so no reminders for a dose you never
  chose. Morning / Afternoon / Night each have − and + buttons and are read out by screen readers.
  "Only when needed" saves the medicine with no reminders.

### 1.23.0 (10 Oct 2026)
- **A "done" moment**: saving a record, scan, reminder, BP/sugar reading, vaccination, family
  member, ABHA or Emergency ID, and turning on backup, shows a tick that draws itself with a word
  ("Record saved"), then fades. "Sent to Dr …" shows the same tick, larger.
- **No light/dark button on the main screens**: choose Follow phone, Light or Dark in
  Me → Appearance.

### 1.22.0 (10 Oct 2026)
- **Photos**: six warm, natural photos, bundled in the app (about 800 KB, no internet): a family
  on the first screen, a report on the table when Records is empty, a doctor looking at a
  patient's phone on Share (until someone has access), a pill organiser when there is nothing
  to take today, a couple reading a report on Insights before it is turned on, and a father
  with his daughter on Add family. They drift in gently, are skipped by screen readers, dim
  slightly in dark mode, and never have text laid over them. The photos are AI-generated (Canva);
  they are not real patients.

### 1.21.0 (10 Oct 2026)
- **Swipe to tick**: on Reminders, swipe a medicine or reminder sideways to mark it taken (swipe
  again to undo). Ticked items fade and are struck through. The checkbox still works.
- **Pull down on Share** to collect prescriptions and family updates; the button is now called
  "Check for prescriptions and updates".
- **Touchable trend chart**: touch or drag along the dots to read each result and its date; the
  number rolls to the value under your finger. Dots light up column by column. The scale starts
  at 80% of your lowest result, so a small change no longer looks like a big drop. Screen readers
  hear every value and date.

### 1.20.0 (10 Oct 2026)
- **Every tab is labelled**: the bottom bar shows each icon with its name; the selected one sits
  on the lime pill. The light/dark button moved to a new top bar beside the LifeTrack name.
- **Feels responsive**: cards and buttons sink slightly under the finger, important buttons give
  a light haptic tap, tabs and cards fade in. Animations are off when the phone asks for less
  motion.
- **Easier to tap and read at large text sizes**: buttons grow to two lines instead of cutting
  the label; chips and round buttons are at least 48 dp.
- 1.19.1 left the version shown on Me at 1.19.0; fixed.

### 1.19.1 (10 Oct 2026)
- **Whose records, on every tab**: with more than one person on the phone, Share and Insights
  show "Viewing Aarav Sharma · son" with a Switch button. The doctor-share screen starts with
  "Sharing Aarav Sharma's records" and the button names the person, level and time
  ("Share Aarav's Summary with Dr Mehta · 1 hour").
- **Emergency ID**: a Call button opens the dialer with the contact's number; empty fields say
  "Not filled in" instead of "—"; the card now says a locked phone hides it and how to keep a
  copy outside the phone. The "A stranger can read this" warning is readable in dark mode.
- **Insights** shows "could not run · Try again" instead of spinning forever on a failure.
- Contrast test now covers the Emergency ID editor and Show on my phone.

### 1.19.0 (3 Oct 2026)
- **Choose how long a doctor can see your records**: 1 hour (default), 4 hours, 12 hours,
  1 day or 2 days, picked when you share. When a doctor asks by LifeTrack ID, their asked-for
  time is preselected and shown ("asked for 12 hours, you can give less").
- **Change the time later**: Share → Who has access → Time. Longer or shorter, counted from
  now; the doctor's copy is replaced with one that ends at the new time. Shares made before
  1.19.0 need the doctor's code scanned again.

### 1.18.3 (3 Oct 2026)
- **Back works like other apps**: from Records, Insights, Share or Me, back returns to
  Reminders; on Reminders, "Press back again to exit". Pages opened on top still close first.
  Before, back from any tab closed the app.

### 1.18.2 (3 Oct 2026) — fixes from the review of 1.18.1
- **Shares prove who sent them**: a share that carries a LifeTrack ID now also carries a proof
  (HMAC under X25519(reply key, doctor's key), bound to the grant and the ID) that it came from
  the phone holding the reply key. The registry lookup is public, so ID + key alone could be
  copied into a fake share.
- **An old family link no longer stops the others**: updates skip links made before 1.18.1, and
  one failed send no longer ends the round.
- **Unlinking an old family link still deletes the other phone's copy** (#1e): the unlink goes
  without a secret, and is accepted unproven for an unsecured link only — it can only delete.
- **Server**: `--trust-proxy` counts rate limits per `X-Forwarded-For` caller (last hop) when a
  proxy you run is in front, instead of everyone sharing 127.0.0.1's budget. Opening, replacing
  and deleting backups are rate-limited per caller; wrong opens of account codes that do not
  exist are no longer written to the failure file.

### 1.18.1 (3 Oct 2026) — security
- **DigiLocker check needs the hand-back code**: the page that ends the sign-in shows an
  8-character code; the result is released only to the app it is typed into. Before, someone
  could start a check, send its link to another person, and collect THAT person's signed
  identity when they signed in. Five wrong codes end the check.
- **Family links are proven**: accepting an invite makes a link secret, sent sealed to the
  inviter only; every update and unlink must carry it. Someone who saw the invite code (often
  sent over a chat app) can no longer send a fake Emergency ID or medicines, or unlink. Both
  phones show a safety code for the link. What a linked phone sends is cut to the Emergency ID
  fields (bounded) and at most 50 medicine names. Links made before 1.18.1 must be made again.
- **Revoked doctors refused while online**: before a scan, a share, a prescription or an access
  request is accepted, the phone asks the registry whether the doctor is still approved with
  the same keys. Offline, the certificate decides — and certificates now last 30 days, not 365.
- **No screen lock, no records**: on a phone with no PIN, pattern, fingerprint or face lock the
  app asks for one instead of opening straight in (the Emergency ID stays one tap away). Demo
  builds still open.
- **Storage**: every sealed blob is bound to its name (AES-GCM associated data, frame v2), so a
  blob copied under another name — or a page moved to another record — no longer opens; older
  blobs are rewritten bound the first time they are read. The index of names is sealed too.
- Files shared to LifeTrack are read in bounded chunks (25 MB each, 60 MB held at once) instead
  of whole before the size check.
- Plane C: a result whose unit is not a known unit stays home (a unit field is free text).
- Refused inbox messages name their reason in the access log.
- **Server**: enrolments waiting for review cannot be replaced; revocation follows the keys
  (re-enrolling a number never revives an old certificate); certificates renew automatically;
  signed pickups carry a one-time nonce; a relay deposit never replaces another; mailbox and
  relay sizes are bounded; per-client rate limits (ID lookups 60/min, enrolments 10/hour, …);
  body sizes capped before reading; backups keep only a hash of the password verifier and
  wrong proofs on replace and delete count towards the 10/hour lockout, which survives a
  restart; browsers may call only from loopback pages or `--allow-origin`s, and only under
  loopback Host names or `--public-base` (no DNS rebinding); admin token compared in constant
  time; bad admin bodies are 4xx, not crashes.

### 1.18.0 (2 Oct 2026)
- **Light/dark in one tap**: a sun/moon button beside the tab bar on every main screen
  switches between light and dark, and remembers. "Follow phone" stays on Me → Appearance.

### 1.17.0 (2 Oct 2026)
- **Scan a report or prescription**: add pages from the camera, photos, any file (PDF or
  photo), or share straight to LifeTrack from WhatsApp, Gmail or Files. LifeTrack reads them
  on the phone (Tesseract, bundled; nothing is sent) and fills the form: kind, report name,
  lab or clinic, doctor, sample date, each value with unit and printed range, and for a
  prescription each medicine with dose, food timing and days. Anything it is unsure of is
  highlighted with what it read; each must be ticked or corrected, then "This matches my
  report" saves it with the photo. Handwriting is flagged and nothing on it is trusted
  unticked. 24 more tests in the list (CBC, liver, kidney, thyroid, electrolytes, B12).
  A prescription with several medicines saves one record per medicine on the same pages.
  Android only for now; on iPhone the form is filled by hand as before.

### 1.16.0 (1 Oct 2026)
- **Dark mode**: Me → Appearance — Follow phone, Light or Dark. Switching keeps the screen
  you are on. Dark pages and cards; hero cards lifted; primary buttons cream; lime still means
  "now". Orange/green status text in lighter, colour-blind-checked shades; QR codes stay black
  on white. Every main screen passes the contrast test in both modes.

### 1.15.1 (1 Oct 2026)
- Readability: nothing dark on the black cards any more (badges such as "Course finished"
  switch to light on dark), grey labels and placeholders darkened to WCAG AA (4.5:1),
  disabled buttons stay readable. A contrast test checks every main screen.
- Doctors show by name ("Dr. Priya Nair · DMC-67890") in Who has access and the access log.
- Errors read in plain words ("LifeTrack's server could not be reached…"), not exception text.
- Family overview: "Open now" readable on the head's black card. Results over time: buttons
  wrap instead of overflowing on large text.

### 1.15.0 (1 Oct 2026)
- **Family overview** (family bar → people icon, or Me): the phone owner is the head of family;
  grandparents and parents above, the head's own generation (spouse, brothers, sisters), then
  children and grandchildren. Each person: role, age, LifeTrack ID, verified or declared,
  records, medicines now, vaccines due, next reminder. Tap to open their records.
- **Roles to the head**: when adding someone you pick who they are to the head — father,
  mother, wife, husband, brother, sister, son, daughter, grandparents, in-laws, grandchildren,
  uncle, aunt, nephew, niece, cousin. Change a role later from the overview (logged).
- A child under 18 is still added only by their parent (son or daughter of the head).

### 1.14.0 (1 Oct 2026)
- A share now carries the patient's LifeTrack ID, so the doctor can ask for access again later
  (the patient still approves every request).

### 1.13.0 (1 Oct 2026) — security
- Hide from screenshots (Me): screenshots, screen recordings and the Recent apps preview come
  out blank. On by default; demo builds start with it off so demos can be recorded.
- Emergency ID is now encrypted on the phone like everything else (still readable from the
  lock screen). Cards saved by older versions are encrypted the first time they are read.
- Export can be password-protected (on by default): AES-256 zip, password made by the app and
  shown once.
- No plain copies left behind: the camera's photo file and a picked PDF are deleted once read,
  the Emergency ID image after sharing, and leftovers are swept when the app opens.
- Release builds are obfuscated (`scripts/build_apk.sh`).
- Server: the data folder (ID map, doctor enrolments, backups, keys) is owner-only.

### 1.12.0 (1 Oct 2026)
- Records: tapping a trend tile shows that test in the big black card (the latest is marked
  "Latest" among the tiles); tapping the big card opens every result.

### 1.11.0 (1 Oct 2026)
- Sample data has more history: six tests with three results (HbA1c, total cholesterol, LDL,
  HDL, triglycerides, fasting glucose) and four with two (TSH, haemoglobin, vitamin D,
  creatinine). Demo builds: Me → Add sample records adds or updates them in place.
- Fix: sharing All my reports with a test filter sent every report in the date range; now only
  reports carrying a chosen test travel (prescriptions and scans stay home).

### 1.10.1 (1 Oct 2026)
- Results over time: the doctor's name no longer reads "Dr: Dr. …".

### 1.10.0 (1 Oct 2026)
- Every test with more than two results gets a trend on Records automatically (the most
  recent as the big card, others as tiles). Tap one for every result: value, date, how long
  ago, lab, doctor, source, and one tap to the report or its original photo/PDF.
- Tests you already have: each test opens the same history.

### 1.9.0 (1 Oct 2026)
- Create your own reminders (what, optional note, one or more times, every day / some days /
  once, optional end date); edit, pause or delete them. Today's ones are ticked off on the
  Reminders tab. Kept on the phone; backed up only with personal notes.
- Each medicine in Today's medicines has an edit button that opens its prescription.

### 1.8.0 (1 Oct 2026)
- Reminders is its own tab, first in the bar, and the app opens on it: today's medicines to tick
  off, vaccinations due, what is coming up, and the reminder settings. Records no longer
  repeats them.

### 1.7.0 (1 Oct 2026)
- Import lab reports from a PDF; pages kept as the original.
- "Tests you already have" card: age, lab and source of every result.
- BP & sugar diary with chart; "Home readings" share level (off unless ticked).

### 1.6.0 (1 Oct 2026)
- Edit and delete records (doctor-signed records are kept as issued).
- Medicine reminders and today's checklist; names hidden on the lock screen by default.
- Child vaccination schedule (India UIP) with due-day reminders.

### 1.5.0 (1 Oct 2026)
- Profiles made only from a DigiLocker verification (Aadhaar); newborns from the parent's
  DigiLocker birth certificate.

### 1.4.0 (1 Oct 2026)
- 12-digit LifeTrack ID per profile; verified doctors can request access by ID.

### 1.3.0 (1 Oct 2026)
- Encrypted backup and restore with an app-generated password and recovery codes.

### 1.2.0 (1 Oct 2026)
- ABHA number field (not verified), Emergency ID QR and wallet card.

### 1.1.0 (30 Sep 2026)
- App lock, export of all records, access log split into views, family links, spacing fixes.

### 1.0.0 (29 Sep 2026)
- Rebuilt phase-2 app: records, insights, consent, clinical sharing with verified doctors.

## Doctor web app

### 1.8.0 (3 Oct 2026)
- **Profile tab** (like Me in the patient app): who you are as the registry approved you
  (name, speciality, registration, council, verified, certificate renewal date), practice
  details, privacy, appearance, this device (key fingerprint, patients, prescriptions, notes),
  demo tools, version, and Start over (now asks first).
- **Practice details**: qualification, clinic, address and phone, editable any time. Printed on
  paper prescriptions; the qualification fills in each new prescription.
- **Hide from screenshots is a setting** (Profile → Privacy), as in the patient app: on by
  default, off by default in demo builds so demos can be recorded. Before, screenshots were
  always blocked.
- My code now shows only your code; Appearance and Demo moved to Profile.

### 1.7.0 (3 Oct 2026)
- **Ask for a time**: Request access by LifeTrack ID → For how long (1 hour by default, up to
  2 days). The time is signed with the request; the patient may give less.
- When the patient changes the time of a share, the new one replaces the old without an
  "ended access" message.

### 1.6.1 (3 Oct 2026)
- **Back works like other apps**: an open patient closes first, then Prescriptions or My code
  return to Patients, and on Patients "Press back again to exit". Before, back closed the app,
  even from a patient's page.

### 1.6.0 (3 Oct 2026)
- **Named LifeTrack Clinic**, shown as "LT Clinic" on the home screen. It gets its own icon:
  the patient app's card deck with ℞ on the front card, the pulse line forming the ℞'s cross
  stroke and ending in the lime "now" dot. Android adaptive icon, legacy icons and web icons
  are all updated. The web manifest no longer uses Flutter's blue.

### 1.5.1 (3 Oct 2026)
- Demo builds: "Use a sample doctor" on the sign-up screen fills in a sample name, speciality,
  council and a fresh registration number. Approval still comes from the registry.

### 1.5.0 (3 Oct 2026)
- **Sample patients** (demo builds only, `LT_DEMO_TOOLS=true`): My code → Add sample patients
  fills the app with six made-up patients, each named "(sample)". Three have access open with a
  full summary (diabetes with home readings, heart disease with family illnesses, anaemia with
  all reports), three are closed in the register. Six prescriptions signed on this device and
  four consult notes with follow-ups. Adding again replaces the samples; real patients are
  untouched.

### 1.4.2 (3 Oct 2026) — fixes from the review of 1.4.1
- **A share is "confirmed" only with the sender's proof**: matching the registry's key was not
  enough, because anyone can look that key up. The share must also prove it was made with the
  reply key's private half; without that it is filed apart as "identity not confirmed".
- **A revocation survives a restart**: the certificate is dropped and the reason kept, so the
  app stays "Not approved" instead of showing itself approved and failing every pickup.

### 1.4.1 (3 Oct 2026) — security
- **Shares are checked against the patient's LifeTrack ID**: a share is filed under its ID only
  when the registry has that ID registered to the key the share asks replies to go to. Anything
  else is shown as "(identity not confirmed)" and kept apart, so a forged share can no longer
  replace a real patient's open share or receive the prescription written for them.
- One item that cannot be opened no longer loses the rest of a pickup.
- Close messages need the patient's secret (a missing one no longer matches).
- **Key fingerprint** on the waiting screen, to read back to the reviewer before approval.
- Certificates (now 30 days) are renewed automatically; a number approved for another device
  stops this one.
- **Android**: opens behind the phone's lock (fingerprint, face or PIN; a phone with no screen
  lock is asked to set one, except in `LT_DEMO_TOOLS` builds), relocks after a minute away;
  FLAG_SECURE always on; cloud backup and device transfer refused.
- Pickups are signed with a one-time nonce.

### 1.4.0 (1 Oct 2026)
- **Dark mode**: My code → Appearance (Follow device, Light, Dark). The verified QR stays black
  on white.
- **Android app** "Doctor" (health.lifetrack.doctor) from the same code; its storage key lives
  in the phone's keystore. Name and logo to come.
- The session is loaded once, not on every redraw.

### 1.3.1 (1 Oct 2026)
- Grey text and placeholders darkened to WCAG AA; contrast test added.
- The patient page shows the summary and the prescription side by side on a 1280 px laptop.

### 1.3.0 (1 Oct 2026)
- **My patients**: everyone who has shared with you — open shares first with time left, then
  the whole register (last shared, how many times, prescriptions, next follow-up). Search by
  name or LifeTrack ID. A closed patient can be asked for access again in one tap.
- **Prescriptions**: every prescription you signed, searchable; print again, or write it again
  for the same patient while their access is open.
- **Consult notes**: private notes per visit (complaint, findings, plan, follow-up date); add,
  edit, copy, delete. Never sent to the patient or LifeTrack.
- **Phone layout**: bottom bar (Patients · Prescriptions · My code) on narrow screens.
- **Encrypted storage**: keys, inbox, register, prescriptions and notes are sealed with a
  non-extractable WebCrypto key kept in this browser; values saved in the clear by older
  versions are sealed on first read. Start over deletes the key.

### 1.2.0 (1 Oct 2026)
- Print or save a signed prescription as a PDF.

### 1.1.0 (1 Oct 2026)
- Inbox kept between visits; shares close when the patient ends access; request access by
  LifeTrack ID; home readings and PDF labels in the summary.

### 1.0.0 (30 Sep 2026)
- Enrolment, registry verification, opening shares, signed prescriptions.
