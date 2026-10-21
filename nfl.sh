#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

ARCHIVE="$SCRIPT_DIR/archive.txt"

# A season runs September to February, so January to June belong to the
# previous year's season. config.sh can set these to override them
TODAY=$(date -u +%F)
if [ -z "$SEASON" ]; then
  SEASON=${TODAY:0:4}
  if [ "$((10#${TODAY:5:2}))" -le 6 ]; then
    SEASON=$((SEASON - 1))
  fi
fi

# Week 1 opens on the Thursday after Labor Day (the first Monday in
# September), so weeks start on the Wednesday two days after it
if [ -z "$SEASON_START" ]; then
  for DAY in 1 2 3 4 5 6 7; do
    if [ "$(date -ud "$SEASON-09-0$DAY" +%u)" -eq 1 ]; then
      SEASON_START=$(date -ud "$SEASON-09-0$DAY + 2 days" +%F)
      break
    fi
  done
fi

LIBRARY_DIR=${LIBRARY_DIR:-"$LIBRARY_ROOT/$SEASON NFL"}

# Both drives are mounted with nofail: if one is missing, its mount point is an
# empty directory on the SD card, and we'd silently fill the SD card instead
for MOUNT in "$TMP_MOUNT" "$LIBRARY_MOUNT"; do
  if ! mountpoint -q "$MOUNT"; then
    echo "$MOUNT is not mounted, aborting" >&2
    exit 1
  fi
done
mkdir -p "$TMP_DIR"

# Record every video already in the library, so files moved or added by hand
# are never downloaded again, and the archive can be rebuilt if it's lost
touch "$ARCHIVE"
{
  cat "$ARCHIVE"
  find "$LIBRARY_ROOT" -type f | grep -o '\[[A-Za-z0-9_-]\{11\}\]\.[a-z0-9]*$' | cut -c2-12 | sed 's/^/youtube /'
} | sort -u > "$ARCHIVE.new" && mv "$ARCHIVE.new" "$ARCHIVE"

# Keep yt-dlp current so YouTube extractor changes don't break downloads
yt-dlp -U

# Library folder for a video. Playoff rounds are numbered on from the regular
# season, e.g. "2026 - Week 19 Wild Card Round". The round or week comes from
# the title, or else from the publish date, counting Wednesday-to-Tuesday weeks
# from SEASON_START (the Wednesday before week 1). Prints nothing for
# preseason games, which shouldn't be downloaded
folder_for() {
  local TITLE="$1" PUBLISHED="$2" WEEK
  local WILD_CARD=$((REGULAR_WEEKS + 1))
  local SUPER_BOWL=$((REGULAR_WEEKS + 4))

  if [[ "$TITLE" =~ [Pp]reseason|Hall\ of\ Fame ]]; then
    return
  elif [[ "$TITLE" =~ Wild\ Card ]]; then
    WEEK=$WILD_CARD
  elif [[ "$TITLE" =~ Divisional ]]; then
    WEEK=$((WILD_CARD + 1))
  elif [[ "$TITLE" =~ Championship ]]; then
    WEEK=$((WILD_CARD + 2))
  elif [[ "$TITLE" =~ Super\ Bowl ]]; then
    WEEK=$SUPER_BOWL
  elif [[ "$TITLE" =~ [Ww]eek\ ([0-9]+) ]]; then
    WEEK=$((10#${BASH_REMATCH[1]}))
  else
    local START NOW
    START=$(date -ud "$SEASON_START" +%s)
    NOW=$(date -ud "$PUBLISHED" +%s)
    WEEK=$(( (NOW - START) / 604800 + 1 ))
    # Before week 1 means preseason; the Super Bowl comes after a bye week
    if [ "$WEEK" -lt 1 ]; then
      return
    elif [ "$WEEK" -gt "$SUPER_BOWL" ]; then
      WEEK=$SUPER_BOWL
    fi
  fi

  local NAME
  case $((WEEK - REGULAR_WEEKS)) in
    1) NAME="Wild Card Round" ;;
    2) NAME="Divisional Round" ;;
    3) NAME="Championship Round" ;;
    4) NAME="Super Bowl" ;;
    *) NAME="Highlights" ;;
  esac
  printf "%s - Week %02d %s" "$SEASON" "$WEEK" "$NAME"
}

# Progress bars only make sense in a terminal; under cron they flood the log
PROGRESS=()
if [ ! -t 1 ]; then
  PROGRESS=(--no-progress)
fi

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

    WEEK_DIR=$(folder_for "$TITLE" "$PUBLISHED")
    if [ -z "$WEEK_DIR" ]; then
      continue
    fi

    # Fragments and merging happen on the scratch drive; only the finished
    # file is written to the library. stdin is closed so ffmpeg can't eat the
    # rest of the video list
    echo "Downloading: $TITLE -> $WEEK_DIR"
    yt-dlp -S "res,fps,br" -f "bv*+ba/b" --merge-output-format mkv "${PROGRESS[@]}" \
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
