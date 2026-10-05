#!/bin/sh
# Builds the Word file, then a PDF whose contents page has real page numbers.
# Needs node, LibreOffice (soffice) and poppler (pdftotext).
set -e
cd "$(dirname "$0")"
T=$(mktemp -d)
HEADINGS_OUT="$T/headings.json" node build.js
cp LifeTrack_Health_NTCC_Report.docx "$T/draft.docx"
soffice --headless --convert-to pdf --outdir "$T" "$T/draft.docx" >/dev/null 2>&1
python3 - "$T" <<'PY'
import json, subprocess, sys
t = sys.argv[1]
heads = json.load(open(f'{t}/headings.json'))
n = int([l for l in subprocess.run(['pdfinfo', f'{t}/draft.pdf'], capture_output=True, text=True).stdout.splitlines() if l.startswith('Pages:')][0].split()[1])
pages = {}
norm = lambda s: ' '.join(s.split())
for i in range(1, n + 1):
    lines = [l.strip() for l in subprocess.run(['pdftotext', '-layout', '-f', str(i), '-l', str(i), f'{t}/draft.pdf', '-'], capture_output=True, text=True).stdout.splitlines() if l.strip()]
    if not lines or not lines[-1].isdigit():
        continue  # front matter (roman numerals) or no footer
    folio = lines[-1]
    for _, h in heads:
        if h not in pages and any(norm(l).startswith(norm(h)) for l in lines[:-1]):
            pages[h] = folio
missing = [h for _, h in heads if h not in pages]
if missing:
    sys.exit('headings not found: %s' % missing)
json.dump(pages, open(f'{t}/pages.json', 'w'))
PY
TOC_PAGES="$T/pages.json" OUT="$T/LifeTrack_Health_NTCC_Report.docx" node build.js
soffice --headless --convert-to pdf --outdir "$T" "$T/LifeTrack_Health_NTCC_Report.docx" >/dev/null 2>&1
cp "$T/LifeTrack_Health_NTCC_Report.pdf" .
rm -rf "$T"
echo "wrote LifeTrack_Health_NTCC_Report.docx and LifeTrack_Health_NTCC_Report.pdf"
