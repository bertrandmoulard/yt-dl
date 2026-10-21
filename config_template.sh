# clone this file to "config.sh" and fill out values

API_KEY=
PLAYLIST_ID=
BASE_URL=
QUERY=
MAX_PAGES=10

# Regular season weeks before the playoffs
REGULAR_WEEKS=18

# The season (e.g. 2026) and the Wednesday before week 1 are worked out from
# today's date; set them here only to override that
#SEASON=2026
#SEASON_START=2026-09-09

# Where finished videos go ("<root>/<season> NFL"), and the drive it lives on
LIBRARY_MOUNT=/mnt/bococa
LIBRARY_ROOT=/mnt/bococa/media_library/Sports

# Scratch space for in-progress downloads, and the drive it lives on
TMP_MOUNT=/mnt/downloads
TMP_DIR=/mnt/downloads/yt-dl/tmp
