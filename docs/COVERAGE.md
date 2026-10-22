# Clementine coverage and verification

259 routes passed; 16 Pages routes reserved for manual checks; 0 failures.

The capability registry contains the 275 conversion routes in Tangerine's public format matrix, plus HTML, Keynote, and Numbers inputs. The integration test generates local fixtures for every reference input and checks nonempty/readable outputs. This establishes basic conversion coverage, not identical output quality on arbitrary files.

Pages automation was excluded from the final run at the user's request. No automated tests launch Pages, Numbers, or Keynote. Those adapters remain available when explicitly selecting a native Apple format in the app.

## Conversion routes

| Input | Passed | Manual | Failed |
| --- | ---: | ---: | ---: |
| jpg | 7 | 0 | 0 |
| png | 7 | 0 | 0 |
| webp | 7 | 0 | 0 |
| heic | 7 | 0 | 0 |
| tiff | 7 | 0 | 0 |
| avif | 7 | 0 | 0 |
| bmp | 7 | 0 | 0 |
| svg | 8 | 0 | 0 |
| mp3 | 7 | 0 | 0 |
| m4a | 7 | 0 | 0 |
| wav | 7 | 0 | 0 |
| flac | 7 | 0 | 0 |
| ogg | 7 | 0 | 0 |
| opus | 7 | 0 | 0 |
| aiff | 7 | 0 | 0 |
| wma | 7 | 0 | 0 |
| mp4 | 7 | 0 | 0 |
| mov | 7 | 0 | 0 |
| mkv | 7 | 0 | 0 |
| webm | 7 | 0 | 0 |
| avi | 7 | 0 | 0 |
| wmv | 7 | 0 | 0 |
| gif | 6 | 0 | 0 |
| pdf | 8 | 1 | 0 |
| ppt | 3 | 0 | 0 |
| pptx | 3 | 0 | 0 |
| docx | 7 | 1 | 0 |
| pages | 0 | 8 | 0 |
| md | 7 | 1 | 0 |
| rtf | 8 | 1 | 0 |
| rtfd | 8 | 1 | 0 |
| textclipping | 8 | 1 | 0 |
| epub | 5 | 1 | 0 |
| txt | 7 | 1 | 0 |
| xlsx | 4 | 0 | 0 |
| xls | 5 | 0 | 0 |
| ods | 4 | 0 | 0 |
| csv | 4 | 0 | 0 |
| tsv | 4 | 0 | 0 |
| srt | 2 | 0 | 0 |
| vtt | 2 | 0 | 0 |
| zip | 2 | 0 | 0 |
| tar | 2 | 0 | 0 |
| gz | 2 | 0 | 0 |
| rar | 3 | 0 | 0 |

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

## Version 1.1 appearance update

The conversion engines are unchanged. Four focused wheel tests pass, covering rounded drop geometry, gaps between segments, reopening during a closing animation, stale mouse-up dismissals, and immediate closing with Reduce Motion. Orange glass rendering uses AppKit/SwiftUI Liquid Glass on macOS 26. Static bitmap previews approximate the native material. Live GUI inspection is still blocked by Computer Use app access.
