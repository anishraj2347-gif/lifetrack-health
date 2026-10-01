# Changelog

Patient app (`app/`) and doctor web app (`doctor/`). Bump the version with every update:
a new feature raises the middle number, a fix raises the last; the build number (`+N`)
always goes up (Android refuses to install a lower one).

## Patient app

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

### 1.2.0 (1 Oct 2026)
- Print or save a signed prescription as a PDF.

### 1.1.0 (1 Oct 2026)
- Inbox kept between visits; shares close when the patient ends access; request access by
  LifeTrack ID; home readings and PDF labels in the summary.

### 1.0.0 (30 Sep 2026)
- Enrolment, registry verification, opening shares, signed prescriptions.
