# Third-party source and notices

Clementine invokes independently licensed conversion tools as separate processes. Original Clementine code is MIT licensed; these tools and their libraries retain their respective licenses. This directory preserves the exact Homebrew build recipes and collected notices for this release. LibreOffice also carries its complete upstream license files within its nested application.

## Source access

The table below gives direct source locations for the exact bundled versions. Each linked Homebrew recipe supplies its original URL, checksum, patches, build flags and dependency instructions. `sources.json` contains machine-readable source directions and available source hashes. The recipes are release snapshots; use them instead of the latest Homebrew formula when rebuilding these versions. Git-based sources pin their revision in the recipe.

| Component | Version | Upstream source | Build recipe |
| --- | --- | --- | --- |
| aom | 3.15.2 | [Source](https://aomedia.googlesource.com/aom.git) | [Recipe](aom/aom.rb) |
| brotli | 1.2.0_1 | [Source](https://github.com/google/brotli/archive/refs/tags/v1.2.0.tar.gz) | [Recipe](brotli/brotli.rb) |
| cairo | 1.18.6 | [Source](https://cairographics.org/releases/cairo-1.18.6.tar.xz) | [Recipe](cairo/cairo.rb) |
| dav1d | 1.5.4 | [Source](https://code.videolan.org/videolan/dav1d/-/archive/1.5.4/dav1d-1.5.4.tar.bz2) | [Recipe](dav1d/dav1d.rb) |
| exiftool | 13.55 | [Source](https://downloads.sourceforge.net/project/exiftool/Image-ExifTool-13.55.tar.gz) | [Recipe](exiftool/exiftool.rb) |
| ffmpeg | 9.0.1_1 | [Source](https://ffmpeg.org/releases/ffmpeg-9.0.1.tar.xz) | [Recipe](ffmpeg/ffmpeg.rb) |
| fontconfig | 2.18.3 | [Source](https://gitlab.freedesktop.org/fontconfig/fontconfig/-/archive/2.18.3/fontconfig-2.18.3.tar.gz) | [Recipe](fontconfig/fontconfig.rb) |
| freetype | 2.15.0 | [Source](https://downloads.sourceforge.net/project/freetype/freetype2/2.15.0/freetype-2.15.0.tar.xz) | [Recipe](freetype/freetype.rb) |
| fribidi | 1.0.17 | [Source](https://github.com/fribidi/fribidi/releases/download/v1.0.17/fribidi-1.0.17.tar.xz) | [Recipe](fribidi/fribidi.rb) |
| gettext | 1.0 | [Source](https://ftpmirror.gnu.org/gnu/gettext/gettext-1.0.tar.gz) | [Recipe](gettext/gettext.rb) |
| glib | 2.90.1 | [Source](https://download.gnome.org/sources/glib/2.90/glib-2.90.1.tar.xz) | [Recipe](glib/glib.rb) |
| gmp | 6.3.0 | [Source](https://ftpmirror.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz) | [Recipe](gmp/gmp.rb) |
| graphite2 | 1.3.15 | [Source](https://github.com/silnrsi/graphite/releases/download/1.3.15/graphite2-1.3.15.tgz) | [Recipe](graphite2/graphite2.rb) |
| harfbuzz | 14.6.0 | [Source](https://github.com/harfbuzz/harfbuzz/releases/download/14.6.0/harfbuzz-14.6.0.tar.xz) | [Recipe](harfbuzz/harfbuzz.rb) |
| imagemagick | 7.1.2-30 | [Source](https://github.com/ImageMagick/ImageMagick/releases/download/7.1.2-30/ImageMagick-7.1.2-30.7z) | [Recipe](imagemagick/imagemagick.rb) |
| jpeg-turbo | 3.2.0 | [Source](https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.2.0/libjpeg-turbo-3.2.0.tar.gz) | [Recipe](jpeg-turbo/jpeg-turbo.rb) |
| lame | 4.0 | [Source](https://downloads.sourceforge.net/project/lame/lame/4.0/lame-4.0.tar.gz) | [Recipe](lame/lame.rb) |
| libdatrie | 0.2.14 | [Source](https://github.com/tlwg/libdatrie/releases/download/v0.2.14/libdatrie-0.2.14.tar.xz) | [Recipe](libdatrie/libdatrie.rb) |
| libde265 | 1.1.1 | [Source](https://github.com/strukturag/libde265/releases/download/v1.1.1/libde265-1.1.1.tar.gz) | [Recipe](libde265/libde265.rb) |
| libheif | 1.23.3 | [Source](https://github.com/strukturag/libheif/releases/download/v1.23.3/libheif-1.23.3.tar.gz) | [Recipe](libheif/libheif.rb) |
| libpng | 1.6.59 | [Source](https://downloads.sourceforge.net/project/libpng/libpng16/1.6.59/libpng-1.6.59.tar.xz) | [Recipe](libpng/libpng.rb) |
| librsvg | 2.63.3 | [Source](https://download.gnome.org/sources/librsvg/2.63/librsvg-2.63.3.tar.xz) | [Recipe](librsvg/librsvg.rb) |
| libthai | 0.1.30 | [Source](https://linux.thai.net/pub/thailinux/software/libthai/libthai-0.1.30.tar.xz) | [Recipe](libthai/libthai.rb) |
| libtiff | 4.7.2 | [Source](https://download.osgeo.org/libtiff/tiff-4.7.2.tar.gz) | [Recipe](libtiff/libtiff.rb) |
| libtool | 2.6.2 | [Source](https://ftpmirror.gnu.org/gnu/libtool/libtool-2.6.2.tar.xz) | [Recipe](libtool/libtool.rb) |
| libvmaf | 3.2.1 | [Source](https://github.com/Netflix/vmaf/archive/refs/tags/v3.2.1.tar.gz) | [Recipe](libvmaf/libvmaf.rb) |
| libvpx | 1.16.0 | [Source](https://github.com/webmproject/libvpx/archive/refs/tags/v1.16.0.tar.gz) | [Recipe](libvpx/libvpx.rb) |
| libx11 | 1.8.13 | [Source](https://www.x.org/archive/individual/lib/libX11-1.8.13.tar.gz) | [Recipe](libx11/libx11.rb) |
| libxau | 1.0.12 | [Source](https://www.x.org/archive/individual/lib/libXau-1.0.12.tar.xz) | [Recipe](libxau/libxau.rb) |
| libxcb | 1.17.0 | [Source](https://xorg.freedesktop.org/archive/individual/lib/libxcb-1.17.0.tar.xz) | [Recipe](libxcb/libxcb.rb) |
| libxdmcp | 1.1.5 | [Source](https://www.x.org/archive/individual/lib/libXdmcp-1.1.5.tar.xz) | [Recipe](libxdmcp/libxdmcp.rb) |
| libxext | 1.3.7 | [Source](https://www.x.org/archive/individual/lib/libXext-1.3.7.tar.gz) | [Recipe](libxext/libxext.rb) |
| libxrender | 0.9.13 | [Source](https://xorg.freedesktop.org/archive/individual/lib/libXrender-0.9.13.tar.gz) | [Recipe](libxrender/libxrender.rb) |
| little-cms2 | 2.19.1 | [Source](https://downloads.sourceforge.net/project/lcms/lcms/2.19.1/lcms2-2.19.1.tar.gz) | [Recipe](little-cms2/little-cms2.rb) |
| mpg123 | 1.33.7 | [Source](https://www.mpg123.de/download/mpg123-1.33.7.tar.bz2) | [Recipe](mpg123/mpg123.rb) |
| openssl@3 | 3.6.3 | [Source](https://github.com/openssl/openssl/releases/download/openssl-3.6.3/openssl-3.6.3.tar.gz) | [Recipe](openssl@3/openssl@3.rb) |
| opus | 1.6.1 | [Source](https://ftp.osuosl.org/pub/xiph/releases/opus/opus-1.6.1.tar.gz) | [Recipe](opus/opus.rb) |
| pandoc | 3.12.1 | [Source](https://github.com/jgm/pandoc/archive/refs/tags/3.12.1.tar.gz) | [Recipe](pandoc/pandoc.rb) |
| pango | 1.58.2 | [Source](https://download.gnome.org/sources/pango/1.58/pango-1.58.2.tar.xz) | [Recipe](pango/pango.rb) |
| pcre2 | 10.49 | [Source](https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.49/pcre2-10.49.tar.bz2) | [Recipe](pcre2/pcre2.rb) |
| pixman | 0.46.4 | [Source](https://cairographics.org/releases/pixman-0.46.4.tar.gz) | [Recipe](pixman/pixman.rb) |
| svt-av1 | 4.2.0 | [Source](https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v4.2.0/SVT-AV1-v4.2.0.tar.bz2) | [Recipe](svt-av1/svt-av1.rb) |
| webp | 1.6.0 | [Source](https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz) | [Recipe](webp/webp.rb) |
| x264 | r3222 | [Source](https://code.videolan.org/videolan/x264.git) | [Recipe](x264/x264.rb) |
| x265 | 4.3 | [Source](https://github.com/Multicorewareinc/x265/releases/download/4.3/x265_4.3.tar.gz) | [Recipe](x265/x265.rb) |
| xz | 5.8.4 | [Source](https://github.com/tukaani-project/xz/releases/download/v5.8.4/xz-5.8.4.tar.gz) | [Recipe](xz/xz.rb) |
| zstd | 1.5.7_1 | [Source](https://github.com/facebook/zstd/archive/refs/tags/v1.5.7.tar.gz) | [Recipe](zstd/zstd.rb) |
| LibreOffice | 26.8.1.1 | [Source](https://download.documentfoundation.org/libreoffice/src/26.8.1.1/) | Upstream source release |

## Rebuilding and replacing tools

Build each tool using its preserved recipe and upstream build instructions, then run `python3 scripts/package.py` to assemble the app. The package script shows all library-path changes, configuration files, policy files and signing operations performed by Clementine. No converter source is modified by Clementine. Dynamic libraries remain separate files under `Contents/Resources/Tools/lib`; replacement libraries must retain compatible ABIs. Any changed bundle needs to be signed again locally.

Pandoc is built through Cabal as described by its recipe; its Haskell dependencies are resolved by that upstream build. LibreOffice source release directories contain the core, help, dictionary and translation archives; the core release describes external source dependencies. Apple system frameworks and optional Apple office apps are supplied by macOS, not redistributed by Clementine.

## Film and site

The launch film uses original artwork, actual Clementine interface snapshots, and original synthesized music and interaction sounds generated by `scripts/make_launch_audio.py`. No stock music or narration is included. `brag-output/composition/assets/gsap.min.js` is GSAP 3.14.2; its license header and upstream license URL are preserved. GSAP is only used by the editable film composition; the public page has no JavaScript library dependency.
