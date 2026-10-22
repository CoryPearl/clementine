# Clementine 1.2 preview

Editors now update automatically as you work. The manual **Preview result** step and eight-second rendered media excerpts have been removed.

- **Draggable crops:** resize with any border or one of eight handles, move the selection by dragging inside, and enter exact pixel coordinates. Arrow keys nudge by one pixel; Shift nudges by ten. Borders and fields stay synchronized.
- **Live photos:** adjustments, flips, rotation, annotation, backgrounds and blur/solid redaction update the actual canvas. Live and saved photos share one native renderer.
- **Remove Background:** a new image tool and a toggle in Edit Photo/Add Background. Apple's on-device Vision framework finds the foreground; cutouts display over a checkerboard and save as full-resolution transparent PNGs. Subject detection runs once, then its result is cached while editing. A photo without a recognizable subject reports an error.
- **Live media:** native playback applies trim boundaries, speed and video redaction. An audio processing tap applies gain, mono mixing and bleeps during playback. Audio visualization responds to the playing samples. Normalization measures the source once, then playback and saving use the same peak-safe gain. No rendered eight-second excerpt is used.
- **Automatic encoded results:** image and PDF compression refresh their actual encoded result after a short pause in input. Encoding a complete media file happens when saving.
- **PDF organization and metadata:** page order, rotation and proposed metadata update as controls change.

Saved edits create new files; originals are preserved. Automatic subject segmentation may need review around fine hair, translucent materials and crowded scenes.

## Install

Requires **Apple silicon and macOS 26+**. Download **Clementine.zip**, unzip it, and move Clementine into Applications. Quit the previous Clementine process before opening this update.

This remains an **ad-hoc signed, unnotarized preview**. If macOS blocks its first launch, review the source and use System Settings → Privacy & Security → Open Anyway if you choose to run it. The orange icon appears in the menu bar. Accessibility permission enables global drag shortcuts.

## Verification

31 tests passed, zero failures; the separate full 275-route matrix remains opt-in. Checks include native crop mouse events, bounded selections, automatic photo changes, rapid-edit coalescing, canvas/export pixel matching, transparent PNG output from a real subject photograph, cached cutouts, live audio sample processing, audio-tap attachment, video redaction/time ranges, full 12-second playback, and automatic PDF compression. Native layouts were inspected using offscreen snapshots; a complete manual native GUI session was not performed.

Earlier conversion matrix: 259 passed, 16 Pages routes remain manual checks. No Pages, Numbers or Keynote applications were launched by this release's tests. Native-format adapters remain available when explicitly selected.

The package passes deep/strict signature verification and ZIP integrity. Verify the adjacent checksum:

```sh
shasum -a 256 -c Clementine.zip.sha256
```

Original source/artwork: MIT. Bundled converters retain their own licenses; see [ThirdParty](../ThirdParty/README.md) for notices, exact recipes and upstream source directions. Developer ID signing and Apple notarization are still pending.
