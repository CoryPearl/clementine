# Clementine 1.1 preview

Native Swift file conversion, editing, and actions for Apple silicon Macs running macOS 26 or later. This release adds orange native Liquid Glass, rounded wheel segments, smooth opening and closing, and accessibility-aware motion/transparency.

## Install

1. Download **Clementine.zip**, extract it, and move **Clementine.app** into Applications.
2. Open the app. This preview is ad-hoc signed and **not Apple-notarized**. macOS may block it. After reviewing its source, use **System Settings → Privacy & Security → Open Anyway** if you choose to proceed.
3. Find the orange menu-bar icon. Drag a file and tap **Shift** for conversion, **Command** for tools, or **Control** for actions. Release the key and drop on your choice. Enable Accessibility access if macOS requires it for the global shortcuts.

The app includes its conversion engines; no Homebrew installation is required. Original files are preserved by conversions and edits. Native Apple document formats use the corresponding installed Apple apps and may prompt for Automation permission.

## Verification

- 20 engine/UI-state tests pass; the separate full-matrix test is opt-in and skipped in this release's routine run.
- Earlier complete conversion coverage: 259 routes passed, 16 Pages routes remain manual checks. No Apple office applications were launched by the release tests.
- Deep/strict app signature validation and ZIP integrity pass. Signing is ad-hoc, not Developer ID distribution signing.
- Website checked at eight desktop/mobile viewports; no scrolling, script errors, or broken dialog interactions in those checks. Reduce Motion pauses the hero animation.
- The Brag film is 20 seconds / 600 frames with original music; its composition passes runtime, layout, contrast, and four motion assertions. The demonstration uses actual interface snapshots with staged cursor/file motion.

## Known limits

The live native interface was not interactively verified in this environment. Static screenshots approximate Liquid Glass's dynamic backdrop. PDF-to-Office reconstruction is best effort; compressed PDFs are rasterized. See [conversion coverage](COVERAGE.md).

## Source and licenses

Original Clementine code/artwork: MIT. Independently licensed conversion tools retain their own licenses. Exact source directions, versioned build recipes, and collected notices are in [ThirdParty](../ThirdParty/README.md); additional upstream notices remain inside the bundled LibreOffice app. The GitHub source archive includes the Swift app, packaging scripts, website, editable film, and original soundtrack generator.

`Clementine.zip.sha256` accompanies the download. Verify from its containing directory:

```sh
shasum -a 256 -c Clementine.zip.sha256
```

This is a public preview. Developer ID signing and Apple notarization are still required for a normal first-launch experience.
