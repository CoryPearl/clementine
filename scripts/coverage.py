#!/usr/bin/env python3
from pathlib import Path
from collections import Counter
import json
root=Path(__file__).resolve().parents[1]
rows=json.loads((root/'dist/verification/conversions.json').read_text())
counts=Counter(row['status'] for row in rows)
summary=f"{counts['passed']} routes passed; {counts['manual-check']} Pages routes reserved for manual checks; {counts['failed']+counts['unavailable-input']} failures."
text=f'''# Clementine coverage and verification

{summary}

The capability registry contains the 275 conversion routes in Tangerine's public format matrix, plus HTML, Keynote, and Numbers inputs. The integration test generates local fixtures for every reference input and checks nonempty/readable outputs. This establishes basic conversion coverage, not identical output quality on arbitrary files.

Pages automation was excluded from the final run at the user's request. No automated tests launch Pages, Numbers, or Keynote. Those adapters remain available when explicitly selecting a native Apple format in the app.

## Conversion routes

| Input | Passed | Manual | Failed |
| --- | ---: | ---: | ---: |
'''
for source in dict.fromkeys(row['input'] for row in rows):
 c=Counter(row['status'] for row in rows if row['input']==source)
 text+=f"| {source} | {c['passed']} | {c['manual-check']} | {c['failed']+c['unavailable-input']} |\n"
text+='''
## Tool and package checks

The engine test suite exercises image exports and editing, media formats and tools, PDF merging/splitting/page order/individual rotation, metadata rewriting, editable document output, flattened image redaction, audio redaction outside/inside marked ranges, speed/trim duration, cancellation, archive traversal/link rejection, unique output naming, original preservation, and wheel hit testing/pagination.

The package verifier checks deep code signatures and relocates a copy of the entire app to a differently named folder. That copy converts SVG to PNG, images to PDF, and text to PDF with only macOS system directories on PATH. Apple app automation is disabled during verification.

## Interface and fidelity limits

- Original Clementine branding and interface; no Tangerine code or artwork is reused.
- Native renders of the workspace, radial wheel, editor, and settings are inspected for layout. Live UI automation was denied access to Clementine. Finder drag/drop, multi-display behavior, full-screen Spaces, AirDrop, login registration, and Apple app automation need manual verification on this Mac.
- Editable PDF reconstruction extracts text, uses Vision OCR for scanned pages, and preserves supported embedded raster images. Table and complex layout reconstruction is approximate; vector illustrations, equations, unsupported image encodings, and typography may differ.
- PDF compression rasterizes pages and removes text selection/search. PDF metadata cleanup rewrites page content and flattens annotations. Editor notices explain these behaviors before export.
- Video redaction uses solid rectangles. Image redaction supports solid fills or blur; automated face/text detection must be reviewed.
- Archive extraction rejects symlinks, hardlinks, and special files. Password-protected documents and archives are not unlocked automatically.
- This personal Apple silicon build includes macOS 26 conversion engines and is ad-hoc signed. It is not notarized for public distribution.

Detailed machine-readable results are in `dist/verification/conversions.json` and `dist/verification/package.json`.
'''
(root/'docs/COVERAGE.md').write_text(text)
print(summary)
