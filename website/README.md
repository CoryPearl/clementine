# Clementine download page

One viewport, no build step, no analytics, no external fonts or scripts. `index.html` is the complete landing page. `app.js` handles accessible dialogs and user-controlled video playback, including Reduce Motion and background-tab pausing.

Run from the repository root:

```sh
python3 -m http.server 4173 --directory website
```

GitHub Actions deploys this directory to <https://corypearl.github.io/clementine/>. The download points to the versioned GitHub release, not a large file in Git history.

`assets/clementine-film.mp4` is the 20-second Brag film with original music. `hero-loop.mp4` is a small silent cropped derivative. The source, plan, review, soundtrack generator and share copy are in `../brag-output/` and `../scripts/make_launch_audio.py`.

For a new release, update the versioned download URL, release-note link, version label and size. Upload and verify the release before deploying the changed page.
