#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

ARCHIVE="$SCRIPT_DIR/archive.txt"

# Both drives are mounted with nofail: if one is missing, its mount point is an
# empty directory on the SD card, and we'd silently fill the SD card instead
for MOUNT in "$TMP_MOUNT" "$LIBRARY_MOUNT"; do
  if ! mountpoint -q "$MOUNT"; then
    echo "$MOUNT is not mounted, aborting" >&2
    exit 1
  fi
done
mkdir -p "$TMP_DIR" "$LIBRARY_DIR"

# Record every video already in the library, so files moved or added by hand
# are never downloaded again, and the archive can be rebuilt if it's lost
touch "$ARCHIVE"
{
  cat "$ARCHIVE"
  find "$LIBRARY_DIR" -type f | grep -o '\[[A-Za-z0-9_-]\{11\}\]\.[a-z0-9]*$' | cut -c2-12 | sed 's/^/youtube /'
} | sort -u > "$ARCHIVE.new" && mv "$ARCHIVE.new" "$ARCHIVE"

# Keep yt-dlp current so YouTube extractor changes don't break downloads
yt-dlp -U

# Week number from the title, or else from the publish date, counting
# Wednesday-to-Tuesday weeks from SEASON_START (the Wednesday before week 1)
week_for() {
  local TITLE="$1" PUBLISHED="$2"
  if [[ "$TITLE" =~ [Ww]eek\ ([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    local START NOW
    START=$(date -ud "$SEASON_START" +%s)
    NOW=$(date -ud "$PUBLISHED" +%s)
    echo $(( (NOW - START) / 604800 + 1 ))
  fi
}

PAGE_COUNT=0
PAGE_TOKEN=""

while :; do
  # Fetch videos from the playlist
  RESPONSE=$(curl -s -G \
    -d "part=snippet,contentDetails" \
    -d "playlistId=$PLAYLIST_ID" \
    -d "maxResults=50" \
    -d "key=$API_KEY" \
    -d "pageToken=$PAGE_TOKEN" \
    "$BASE_URL")

  # Parse video IDs, publish dates and titles, filtered by the query
  echo "$RESPONSE" | \
    jq -r --arg query1 "$QUERY" \
    '.items[] | select(.snippet.title? and (.snippet.title | test($query1; "i"))) | [.contentDetails.videoId, .contentDetails.videoPublishedAt, .snippet.title] | @tsv' | \
  while IFS=$'\t' read -r ID PUBLISHED TITLE; do
    if grep -qx "youtube $ID" "$ARCHIVE"; then
      continue
    fi

    WEEK=$(week_for "$TITLE" "$PUBLISHED")
    WEEK_DIR=$(printf "%s - Week %02d Highlights" "$SEASON" "$((10#$WEEK))")

    # Fragments and merging happen on the scratch drive; only the finished
    # file is written to the library. stdin is closed so ffmpeg can't eat the
    # rest of the video list
    echo "Downloading: $TITLE -> $WEEK_DIR"
    yt-dlp -S "res,fps,br" -f "bv*+ba/b" --merge-output-format mkv \
      --download-archive "$ARCHIVE" \
      -P "temp:$TMP_DIR" -P "home:$LIBRARY_DIR" \
      -o "$WEEK_DIR/%(title)s [%(id)s].%(ext)s" \
      "https://www.youtube.com/watch?v=$ID" < /dev/null
  done

  # Increment page count and stop after MAX_PAGES pages
  ((PAGE_COUNT++))
  if [ "$PAGE_COUNT" -ge "$MAX_PAGES" ]; then
    break
  fi

  # Check if there's a next page
  PAGE_TOKEN=$(echo "$RESPONSE" | jq -r '.nextPageToken // empty')
  if [ -z "$PAGE_TOKEN" ]; then
    break
  fi
done
