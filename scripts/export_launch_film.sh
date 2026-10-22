#!/bin/sh
# Run after rendering brag-output/brag.mp4 with Hyperframes.
set -eu
cd "$(dirname "$0")/.."
ffmpeg -hide_banner -loglevel error -y -ss 5.8 -i brag-output/brag.mp4 -frames:v 1 -q:v 2 brag-output/brag.jpg
ffmpeg -hide_banner -loglevel error -y -i brag-output/brag.mp4 -i brag-output/brag.jpg \
  -filter_complex "[0:v][1:v]overlay=0:0:enable='eq(n,0)'[v]" \
  -map '[v]' -map '0:a?' -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p \
  -c:a copy -movflags +faststart brag-output/brag.poster.mp4
mv brag-output/brag.poster.mp4 brag-output/brag.mp4
cp brag-output/brag.mp4 website/assets/clementine-film.mp4
ffmpeg -hide_banner -loglevel error -y -ss 3.25 -t 8.5 -i brag-output/brag.mp4 \
  -filter_complex '[0:v]crop=900:1080:900:0,scale=720:864,split[a][b];[a]trim=start=0:end=1,setpts=PTS-STARTPTS[head];[b]trim=start=1:end=8.5,setpts=PTS-STARTPTS[tail];[tail][head]xfade=transition=fade:duration=0.6:offset=6.9[v]' \
  -map '[v]' -an -c:v libx264 -crf 24 -preset slow -pix_fmt yuv420p -movflags +faststart website/assets/hero-loop.mp4
ffmpeg -hide_banner -loglevel error -y -ss 5.8 -i brag-output/brag.mp4 \
  -vf 'crop=900:1080:900:0,scale=720:864' -frames:v 1 -q:v 2 website/assets/hero-poster.jpg
ffmpeg -hide_banner -loglevel error -y -i brag-output/brag.jpg \
  -vf scale=1200:675 -frames:v 1 -q:v 2 website/assets/social.jpg
