# LifeTrack branding

Decided 3 Oct 2026.

| App | Name | Home-screen label | Icon |
|---|---|---|---|
| Patient (`app/`) | LifeTrack | LifeTrack | Three fanned cards (chart, pill, heart with a pulse ending in a lime "now" dot) on `#1A1A18` |
| Doctor (`doctor/`) | LifeTrack Clinic | LT Clinic | The same deck with ℞ on the front card; the pulse is the ℞'s cross stroke and ends in the lime dot |

- `lifetrack-clinic-branding.html`: the options that were considered and the final choice. Open it in a browser.
- `patient-icon-foreground-432.png`: the patient app's adaptive-icon foreground, copied from `app/android/.../drawable-xxxhdpi`.
- `doctor-icon-foreground-432.png`, `doctor-icon-1024.png`: the doctor icon (adaptive foreground, and a full-bleed 1024 px master).
- `make_doctor_icon.py`: makes the doctor foreground from the patient one (needs Pillow). It paints out the heart, draws the ℞, and redraws the lime dot.
  To install the result, resize it to 108/162/216/324/432 px for `drawable-*/ic_launcher_foreground.png`. The legacy
  `mipmap-*/ic_launcher.png` and the web icons are a centre crop of the foreground with a 76 px margin at 432 px.

Rules: no red cross (restricted in India); lime marks only "now"; marks stay inside the central 66% so Android masks don't clip them.
