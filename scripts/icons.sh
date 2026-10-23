#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ICONS="Resources/icons"
PREVIEWS="$ICONS/previews"
APP_ICON="Resources/AppIcon.icns"

SIZES=(
  icon_16x16.png:16
  icon_16x16@2x.png:32
  icon_32x32.png:32
  icon_32x32@2x.png:64
  icon_128x128.png:128
  icon_128x128@2x.png:256
  icon_256x256.png:256
  icon_256x256@2x.png:512
  icon_512x512.png:512
  icon_512x512@2x.png:1024
)

RENDERER=""

die() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
usage: ./scripts/icons.sh <command> [args]

commands:
  build [name...]   render AppIcon.iconset + .icns + 512px preview (default: every SVG in Resources/icons)
  preview           contact sheet in Resources/icons/previews (needs ImageMagick, else lists files)
  select <name>     promote Resources/icons/<name>.icns to Resources/AppIcon.icns
  clean             remove generated iconsets, .icns files, previews and Resources/AppIcon.icns
EOF
}

png_dim() {
  sips -g "$2" "$1" 2>/dev/null | awk -v k="$2" '$1 == k":" {print $2}'
}

detect_renderer() {
  if [[ -n "$RENDERER" ]]; then
    return 0
  fi
  if command -v rsvg-convert >/dev/null 2>&1; then
    RENDERER="rsvg-convert"
  elif command -v magick >/dev/null 2>&1; then
    RENDERER="magick"
  elif command -v convert >/dev/null 2>&1; then
    RENDERER="convert"
  elif command -v qlmanage >/dev/null 2>&1; then
    RENDERER="qlmanage"
  else
    die "no SVG renderer available; install librsvg or imagemagick (brew install librsvg imagemagick)"
  fi
  echo "renderer: $RENDERER"
}

render() {
  local src="$1" out="$2" size="$3"
  local tmp base produced w s
  local -a found
  case "$RENDERER" in
    rsvg-convert)
      rsvg-convert -w "$size" -h "$size" -o "$out" "$src"
      ;;
    magick|convert)
      "$RENDERER" -background none -density 144 "$src" -resize "${size}x${size}" "$out"
      ;;
    qlmanage)
      tmp="$(mktemp -d)"
      base="${src:t}"
      for s in "$size" 64 128 256; do
        qlmanage -t -s "$s" -o "$tmp" "$src" >/dev/null 2>&1 || true
        found=("$tmp"/*.png(N))
        if [[ -s "${found[1]:-}" ]]; then
          break
        fi
        rm -f "$tmp"/*.png(N) 2>/dev/null || true
      done
      found=("$tmp"/*.png(N))
      if (( ${#found} == 0 )); then
        rm -rf "$tmp"
        die "qlmanage produced no thumbnail for $src"
      fi
      produced="${found[1]}"
      w="$(png_dim "$produced" pixelWidth)"
      if [[ "$w" != "$size" ]]; then
        sips -z "$size" "$size" "$produced" >/dev/null
      fi
      mv -f "$produced" "$out"
      rm -rf "$tmp"
      ;;
    *)
      die "unhandled renderer: $RENDERER"
      ;;
  esac
}

assert_png() {
  local png="$1" want="$2" src="$3" min_bytes="${4:-1000}"
  local bytes w h
  if [[ ! -f "$png" ]]; then
    die "expected PNG missing: $png"
  fi
  if (( min_bytes > 0 )); then
    bytes="$(stat -f%z "$png")"
    if (( bytes < min_bytes )); then
      die "$src rendered blank: $png is only ${bytes} bytes"
    fi
  fi
  w="$(png_dim "$png" pixelWidth)"
  h="$(png_dim "$png" pixelHeight)"
  if [[ -z "$w" || -z "$h" ]]; then
    die "cannot read dimensions of $png via sips"
  fi
  if [[ "$w" != "$h" ]]; then
    die "$png is not square (${w}x${h})"
  fi
  if (( w < want )); then
    die "$png is ${w}px but needs >= ${want}px (source: $src)"
  fi
}

cmd_build() {
  local -a names
  local arg f name svg setdir entry file px out
  for arg in "$@"; do
    f="${arg:t}"
    names+=("${f%.svg}")
  done
  if (( ${#names} == 0 )); then
    for f in "$ICONS"/*.svg(N); do
      f="${f:t}"
      names+=("${f%.svg}")
    done
  fi
  if (( ${#names} == 0 )); then
    die "no SVGs found in $ICONS"
  fi
  detect_renderer
  mkdir -p "$PREVIEWS"
  for name in "${names[@]}"; do
    svg="$ICONS/$name.svg"
    if [[ ! -f "$svg" ]]; then
      die "missing source SVG: $svg"
    fi
    setdir="$ICONS/$name/AppIcon.iconset"
    rm -rf "$ICONS/$name"
    mkdir -p "$setdir"
    for entry in "${SIZES[@]}"; do
      file="${entry%%:*}"
      px="${entry##*:}"
      out="$setdir/$file"
      render "$svg" "$out" "$px"
      if (( px >= 128 )); then
        assert_png "$out" "$px" "$svg" 1000
      else
        assert_png "$out" "$px" "$svg" 0
      fi
    done
    iconutil -c icns -o "$ICONS/$name.icns" "$setdir"
    if [[ ! -f "$ICONS/$name.icns" ]]; then
      die "iconutil did not produce $ICONS/$name.icns"
    fi
    render "$svg" "$PREVIEWS/$name.png" 512
    assert_png "$PREVIEWS/$name.png" 512 "$svg"
    echo "built $name: $ICONS/$name.icns + $PREVIEWS/$name.png ($RENDERER)"
  done
}

cmd_preview() {
  local f m=""
  local -a pngs
  for f in "$PREVIEWS"/*.png(N); do
    if [[ "${f:t}" != "contact-sheet.png" ]]; then
      pngs+=("$f")
    fi
  done
  if (( ${#pngs} == 0 )); then
    die "no previews in $PREVIEWS — run: ./scripts/icons.sh build"
  fi
  if command -v montage >/dev/null 2>&1; then
    m="montage"
  elif command -v magick >/dev/null 2>&1; then
    m="magick montage"
  fi
  if [[ -n "$m" ]]; then
    ${=m} -background "#17171C" -fill "#E7E7EA" -label "%f" -tile 3x2 -geometry 512x512+20+42 "${pngs[@]}" "$PREVIEWS/contact-sheet.png"
    echo "wrote $PREVIEWS/contact-sheet.png from ${#pngs} previews"
  else
    echo "ImageMagick not found: contact-sheet.png skipped; open these previews manually:"
    for f in "${pngs[@]}"; do
      echo "  $f"
    done
  fi
  echo "hint: open $PREVIEWS"
}

cmd_select() {
  if (( $# != 1 )); then
    die "usage: ./scripts/icons.sh select <name>"
  fi
  local f="${1:t}" name icns
  name="${f%.svg}"
  icns="$ICONS/$name.icns"
  if [[ ! -f "$icns" ]]; then
    die "no $icns — build first: ./scripts/icons.sh build $name"
  fi
  cp -f "$icns" "$APP_ICON"
  echo "$name" > "$ICONS/.selected"
  echo "selected $name: $icns -> $APP_ICON"
}

cmd_clean() {
  rm -rf "$ICONS"/*/AppIcon.iconset(N) 2>/dev/null || true
  rm -f "$ICONS"/*.icns(N) 2>/dev/null || true
  rm -rf "$PREVIEWS"
  rm -f "$APP_ICON" 2>/dev/null || true
  echo "cleaned generated icon artifacts; source SVGs kept"
}

cmd="${1:-}"
case "$cmd" in
  build)
    if (( $# > 0 )); then shift; fi
    cmd_build "$@"
    ;;
  preview)
    cmd_preview
    ;;
  select)
    if (( $# > 0 )); then shift; fi
    cmd_select "$@"
    ;;
  clean)
    cmd_clean
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
