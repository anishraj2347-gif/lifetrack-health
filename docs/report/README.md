# NTCC project report

`LifeTrack_Health_NTCC_Report.pdf` is the version to submit; `LifeTrack_Health_NTCC_Report.docx` is
the editable copy (Word fills in its table of contents when opened — click Yes).

Rebuild both after editing `build.js` (needs node, LibreOffice and poppler):

    cd docs/report && npm install && ./make_pdf.sh

`make_pdf.sh` builds the Word file, renders it once to find the page of every heading, and prints
those numbers into the PDF's table of contents.

- `fig/` — diagrams (`.dot` sources rendered with Graphviz; `seq.svg` → `seq.png`).
- `shots/` — app screenshots used in Chapter 5.
- Personal details (name, enrolment number, programme, guide, session) are filled in `build.js`; edit them there so a rebuild keeps them.
