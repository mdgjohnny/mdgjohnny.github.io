#!/bin/bash
set -euo pipefail

### CONFIG ###
NOW_PLAYING_FILE="_includes/now-playing.txt"

### Ensure repo root ###
cd "$(git rev-parse --show-toplevel)"

echo "[+] Fetching Spotify access token"

SPOTIFY_ACCESS_TOKEN="$(
  curl -s https://accounts.spotify.com/api/token \
    -H "Authorization: Basic $(printf '%s:%s' "${SPOTIFY_CLIENT_ID}" "${SPOTIFY_CLIENT_SECRET}" | base64 -w0)" \
    -d grant_type=refresh_token \
    -d refresh_token="${SPOTIFY_REFRESH_TOKEN}" \
  | jq -r '.access_token'
)"

if [[ -z "${SPOTIFY_ACCESS_TOKEN}" || "${SPOTIFY_ACCESS_TOKEN}" == "null" ]]; then
  echo "[ERROR] Failed to fetch Spotify access token"
  exit 1
fi

echo "[+] Fetching recently played track"

NOW_PLAYING_JSON="$(
  curl -s "https://api.spotify.com/v1/me/player/recently-played?limit=1" \
    -H "Authorization: Bearer ${SPOTIFY_ACCESS_TOKEN}"
)"

TRACK="$(jq -r '.items[0].track.name // empty' <<< "${NOW_PLAYING_JSON}")"
ARTIST="$(jq -r '.items[0].track.artists[0].name // empty' <<< "${NOW_PLAYING_JSON}")"

if [[ -z "${TRACK}" || -z "${ARTIST}" ]]; then
  echo "[WARN] No recently played track found"
  exit 0
fi

echo "[+] Track: ${TRACK}"
echo "[+] Artist: ${ARTIST}"
echo "[+] Fetching lyrics from Genius"

RAW_LYRICS="$(
  python -m lyricsgenius song "${TRACK}" "${ARTIST}" 2>/dev/null || true
)"

LYRIC="$(
  printf '%s\n' "${RAW_LYRICS}" \
  | awk -v seed="${RANDOM}" '
      BEGIN { srand(seed) }
      /^[[:space:]]*$/ { next }
      /^[[:space:]]*\[/ { next }
      {
        ++n
        if (rand() < 1/n) pick=$0
      }
      END { if (n>0) print pick }
    ' \
  | sed -E '
      s/^[“”"'\''‘’]+//;
      s/[“”"'\''‘’]+$//;
      s/[‘’]/'\''/g;
      s/[“”]/"/g;
      s/—/--/g;
      s/–/-/g;
      s/…/.../g
    '
)"

if [[ -z "${LYRIC}" ]]; then
  echo "[WARN] No lyric selected, aborting"
  exit 0
fi

echo "[+] Selected lyric:"
echo "    ${LYRIC}"

NEW_CONTENT="♪ ${LYRIC}
—${TRACK} by ${ARTIST}"

### Write only if changed ###
if [[ -f "${NOW_PLAYING_FILE}" ]] && diff -q <(printf '%s\n' "${NEW_CONTENT}") "${NOW_PLAYING_FILE}" >/dev/null; then
  echo "[+] No change detected"
  exit 0
fi

printf '%s\n' "${NEW_CONTENT}" > "${NOW_PLAYING_FILE}"
echo "[+] Updated ${NOW_PLAYING_FILE}"

### Git commit ###
git add "${NOW_PLAYING_FILE}"
git commit -m "update now playing lyric"
git push

echo "[+] Done"

