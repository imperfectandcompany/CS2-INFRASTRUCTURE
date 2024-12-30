#!/usr/bin/env bash
#
# Usage:  ./run_surf.sh [easy|skill|rap]
# Defaults to "easy" if no argument is provided.

SERVER_DIR="/home/steam/servers/cs2_surf_easy"
CS2_BIN="$SERVER_DIR/game/bin/linuxsteamrt64/cs2"

PRESET="${1:-easy}"

case "$PRESET" in
  easy)
    PORT=27015
    WORKSHOP_MAP="3125360522"
    WORKSHOP_COLLECTION="3286028107"
    HOSTNAME="[IG] 24/7 Surf | Easy Surf T1-2 | ImperfectGamers.org"
    SV_TAGS="surf,rap,100tick,beginners,fastdl,imperfect,gamers"
    STEAM_TOKEN="####"
    MAPLIST_FILE="maplist_surf_easy.txt"
    ;;
  skill)
    PORT=27016
    WORKSHOP_MAP="3294887860"
    WORKSHOP_COLLECTION="3286030944"
    HOSTNAME="[IG] 24/7 Surf | Skill Surf T2-6 | ImperfectGamers.org"
    SV_TAGS="surf,skill,fastdl,imperfect,gamers"
    STEAM_TOKEN="####"
    MAPLIST_FILE="maplist_surf_skill.txt"
    ;;
  rap)
    PORT=27017
    WORKSHOP_MAP="3070321829"
    WORKSHOP_COLLECTION="3286028107"
    HOSTNAME="[IG] 24/7 Surf | Rap T1-2 | ImperfectGamers.org"
    SV_TAGS="rap,100tick,beginners,fastdl,imperfect,gamers"
    STEAM_TOKEN="####"
    MAPLIST_FILE="maplist_surf_rap.txt"
    ;;
  *)
    echo "[Warn] Unrecognized preset '$PRESET', defaulting to 'easy'..."
    PORT=27015
    WORKSHOP_MAP="3125360522"
    WORKSHOP_COLLECTION="3286028107"
    HOSTNAME="[IG] 24/7 Surf | Easy Surf T1-2 | ImperfectGamers.org"
    SV_TAGS="surf,rap,100tick,beginners,fastdl,imperfect,gamers"
    STEAM_TOKEN="####"
    MAPLIST_FILE="maplist_surf_easy.txt"
    ;;
esac

echo "[Info] Starting preset: $PRESET, on port: $PORT"
cd "$SERVER_DIR" || exit 1

echo "[Info] Launching server with: +rockthevote_maplist_file \"${MAPLIST_FILE}\""

sudo -u steam env LD_LIBRARY_PATH="/home/steam/cs2-base/game/bin/linuxsteamrt64:${LD_LIBRARY_PATH}" \
  "$CS2_BIN" \
    -dedicated \
    -console \
    -usercon \
    -autoupdate \
    -tickrate 128 \
    -port "$PORT" \
    +map de_dust2 \
    +host_workshop_map "$WORKSHOP_MAP" \
    +host_workshop_collection "$WORKSHOP_COLLECTION" \
    +hostname "$HOSTNAME" \
    +sv_tags "$SV_TAGS" \
    -maxplayers 34 \
    +sv_lan 0 \
    +sv_setsteamaccount "$STEAM_TOKEN" \
    -authkey "####" \
    +game_type 0 \
    +game_mode 0 \
    +rockthevote_maplist_file "${MAPLIST_FILE}" \
    +exec autoexec.cfg
