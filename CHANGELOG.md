# Changelog

Patient app (`app/`) and doctor web app (`doctor/`). Bump the version with every update:
a new feature raises the middle number, a fix raises the last; the build number (`+N`)
always goes up (Android refuses to install a lower one).

## Patient app

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
