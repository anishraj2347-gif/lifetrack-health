# NTCC project report

`LifeTrack_Health_NTCC_Report.docx` is the submitted report; `LifeTrack_Health_NTCC_Report_preview.pdf`
is a LibreOffice rendering for checking layout (its table of contents is empty — Word fills it in).

Rebuild after editing `build.js`:

    cd docs/report && npm install && npm run build

- `fig/` — diagrams (`.dot` sources rendered with Graphviz; `seq.svg` → `seq.png`).
- `shots/` — app screenshots used in Chapter 5.
- Yellow `[[...]]` placeholders in `build.js` are fields the team fills in (names, enrolment
  numbers, programme, designation, session, date). Fill them in `build.js` so a rebuild keeps them.
