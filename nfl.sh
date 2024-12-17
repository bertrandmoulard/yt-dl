#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

PAGE_COUNT=0
PAGE_TOKEN=""

while :; do
  # Fetch videos from the playlist
  RESPONSE=$(curl -s -G \
    -d "part=snippet" \
    -d "playlistId=$PLAYLIST_ID" \
    -d "maxResults=50" \
    -d "key=$API_KEY" \
    -d "pageToken=$PAGE_TOKEN" \
    "$BASE_URL")

  # Parse video titles and IDs, filter by both queries only if title exists
  echo "$RESPONSE" | \
    jq -r --arg query1 "$QUERY1" --arg query2 "$QUERY2" \
    '.items[] | select(.snippet.title? and (.snippet.title | test($query1; "i")) and (.snippet.title | test($query2; "i"))) | "\(.snippet.title) - https://www.youtube.com/watch?v=\(.snippet.resourceId.videoId)"' | \
  while IFS= read -r LINE; do
    TITLE=$(echo "$LINE" | awk -F' - ' '{print $1}')
    URL=$(echo "$LINE" | awk -F' - ' '{print $2}')

    # Download the video in MP4 format using yt-dlp
    echo "Downloading: $TITLE"
    yt-dlp -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]" "$URL"
  done

  # Increment page count and stop after 10 pages
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
