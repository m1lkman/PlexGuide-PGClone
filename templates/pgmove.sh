#!/bin/bash
#
# Title:      PlexGuide (Reference Title File)
# Author(s):  Admin9705
# URL:        https://plexguide.com - http://github.plexguide.com
# GNU:        General Public License v3.0
################################################################################
if pidof -o %PPID -x "$0"; then
   exit 1
fi
# Outside Variables
dlpath=$(cat /var/plexguide/server.hd.path)
ver=$(cat /var/plexguide/rclone/deploy.version)
. "$dlpath/gcrypt/.config/cloud/pgcloud.conf"
. "$dlpath/gcrypt/.config/bin/pgcloud.sh"
if [[ ! -e "${HOME}/.cache" ]]; then mkdir -p "${HOME}/.cache"; fi
sleep 10

while true
do
STARTLOOP=$(date)
TIMESTAMP=`date +%Y-%m-%d_%H-%M-%S`
SECTION="MOVETO"
dlpath=$(cat /var/plexguide/server.hd.path)

## Sync, Sleep 2 Minutes, Repeat. BWLIMIT 9 Prevents Google 750GB Google Upload Ban

find "$dlpath/downloads/" -mindepth 1 -type f \
-cmin +0.233 -not -newerct "$STARTLOOP" \
-not -iname '*_HIDDEN~' -not -iname '*unionfs*' \
-not -iname '*.partial~' -not -iname '*unionfs-fuse*' \
-not -iname '.*' \
-not -path '*/sabnzbd/*' -not -path '*/nzbget/*' \
-not -path '*/qbittorrent/*' -not -path '*/rutorrent/*' \
-not -path '*/deluge/*' -not -path '*/transmission/*' \
-not -path '*/jdownloader/*' -not -path '*/makemkv/*' \
-not -path '*/handbrake/*' -not -path '*/bazarr/*' \
-not -path '*ignore*'  -not -path '*inProgress*' \
> ${HOME}/.cache/$TIMESTAMP-files-from.list

if [[ -s "${HOME}/.cache/$TIMESTAMP-files-from.list" ]]; then
    sed -i "s@$dlpath/downloads/@@g" ${HOME}/.cache/$TIMESTAMP-files-from.list
    rclone moveto "$dlpath/downloads/" "$dlpath/move/" \
    --config /opt/appdata/plexguide/rclone.conf \
    --log-file=/var/plexguide/logs/pgmove.log \
    --log-level INFO --stats 5s --stats-file-name-length 0 \
    --files-from=${HOME}/.cache/$TIMESTAMP-files-from.list
    if [[ $? -eq 0 ]]; then
        log "SUCCESS: rclone moveto to $dlpath/move/"
    else
        log "ERROR: rclone moveto to $dlpath/move/ failed: $?"
    fi
else
    log "No files found for local moveto"
    rm ${HOME}/.cache/$TIMESTAMP-files-from.list
fi

if [[ -d "/opt/plexguide/plex" ]]; then

    SECTION="PLEX MEDIA SCANNER"

    while [ $(docker inspect -f '{{.State.Running}}' plex) = "false" ]; do
        log "Plex Container Not Running, sleeping 10 minutes"
        sleep 10m
    done
    log "Plex Container Running"
fi

SECTION="RCLONE MOVE"
readarray -t LOCALFILES < <(find "$dlpath/move/" -mindepth 1 -type f -cmin +0.233 -not -newerct "$STARTLOOP" -not -iname '*.partial~' -not -iname '*_HIDDEN~' -not -iname '*.QTFS' -not -iname '*unionfs-.fuse*' -not -iname '*unionfs*' -not -iname '*.DS_STORE')
if [[ -n $LOCALFILES ]]; then

    if [[ -d "/opt/plexguide/plex" ]]; then log "${#LOCALFILES[@]} local file/s found for Plex Media Scanner"; fi
    # Create empty array
    MEDIAFOLDERS=()
    for LOCALFILE in "${LOCALFILES[@]}" #Populate array with paths to plex library folders
    do
            LOCALFILESHORTNAME="$(echo "$LOCALFILE" | sed -e s@$dlpath/move/@@)"
            echo "$LOCALFILESHORTNAME" >> ${HOME}/.cache/$TIMESTAMP-files-from.list
            log "Adding ""$mediadir/$(dirname "$LOCALFILESHORTNAME")"" to scanner array"
            MEDIAFOLDERS+=("$mediadir/$(dirname "$LOCALFILESHORTNAME")")
    done
    readarray -t MEDIAFOLDERS < <(printf "%s\n" "${MEDIAFOLDERS[@]}" | sort -u)
    if [[ -d "/opt/plexguide/plex" ]]; then

        log "${#MEDIAFOLDERS[@]} Unique folder/s found for Plex Media Scanner"
        for MEDIAFOLDER in "${MEDIAFOLDERS[@]}"
        do
            log "Start Plex Media Scanner for folder: $MEDIAFOLDER"
            libraryfolder=$(echo $(echo $MEDIAFOLDER | sed -e s@$mediadir/@@) | cut -d '/' -f 1)
            libraryfolder_nospaces=$(echo "$libraryfolder" | sed -e 's/ //g')
            section_varname="${libraryfolder_nospaces}SECTION"
            if [[ -d "$(echo $MEDIAFOLDER | sed -e s@$mediadir/@$libraryroot/@)" ]] && [[ -n ${!section_varname} ]]; then
                docker exec -u 1000:1000 \
                -e LD_LIBRARY_PATH=/usr/lib/plexmediaserver/lib \
                -e PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR=/config/Library/Application\ Support \
                -i plex /usr/lib/plexmediaserver/Plex\ Media\ Scanner \
                --scan --refresh --section "${!section_varname}" --directory "$MEDIAFOLDER"
                if [[ $? -eq 0 ]]; then
                    log "SUCCESS: Plex Media Scanner successful for media folder $MEDIAFOLDER"
                    slack_message "Upload Completed to Cloud Drive" "" "" "${#UPLOADFILES[@]} file/s uploaded in $(printf '%dh:%dm:%ds\n' $(($(($(date +'%s') - $(date -d "$RCLONESTART" +'%s')))/3600)) $(($(($(date +'%s') - $(date -d "$RCLONESTART" +'%s')))%3600/60)) $(($(($(date +'%s') - $(date -d "$RCLONESTART" +'%s')))%60)))" "$HOSTNAME" "" "$SCRIPTNAME" ""
                else
                    log "ERROR: Error executing Plex Media Scanner ERROR: $?"
                fi
            elif [[ -z ${!section_varname} ]]; then
                    log "SKIP: No existing Plex Media Library Section found for media folder $MEDIAFOLDER"
            elif [[ ! -d "$(echo $MEDIAFOLDER | sed -e s@$mediadir@$libraryroot@)" ]]; then
                    log "SKIP: Plex Media Library folder $MEDIAFOLDER not found for scanner"
            fi
        done
    fi
fi

if [[ -s "${HOME}/.cache/$TIMESTAMP-files-from.list" ]]; then
    FILECOUNT=$(wc -l "${HOME}/.cache/$TIMESTAMP-files-from.list" | awk '{ print $1 }')
    log "Moving $FILECOUNT local file/s to $ver:/"
    RCLONESTART=$(date)
    rclone move "$dlpath/move/" "$ver:/" \
    --config /opt/appdata/plexguide/rclone.conf \
    --log-file=/var/plexguide/logs/pgmove.log \
    --log-level INFO --stats 5s --stats-file-name-length 0 \
    --files-from=${HOME}/.cache/$TIMESTAMP-files-from.list \
    --bwlimit 9M \
    --tpslimit 6 \
    --checkers=16 \
    --max-size=300G \
    --no-traverse
    if [[ $? -eq 0 ]]; then
        log "SUCCESS: rclone move to $ver:"
        json=$(slack_message "Rclone move completed to Google Drive ($ver:)" "" "" "$FILECOUNT file/s uploaded in $(printf '%dh:%dm:%ds\n' $(($(($(date +'%s') - $(date -d "$RCLONESTART" +'%s')))/3600)) $(($(($(date +'%s') - $(date -d "$RCLONESTART" +'%s')))%3600/60)) $(($(($(date +'%s') - $(date -d "$RCLONESTART" +'%s')))%60)))" "$HOSTNAME" "" "$SCRIPTNAME" "")
        thread_ts=$(echo $json | python -c 'import sys, json; print json.load(sys.stdin)["message"]["ts"]')
        slack_upload "${HOME}/.cache/$TIMESTAMP-files-from.list" "$TIMESTAMP-files-from.list" "List File Contents" "$HOSTNAME" $thread_ts
        cat ${HOME}/.cache/*.list > $dlpath/gcrypt/.cache/$TIMESTAMP-files-to.list
        rm ${HOME}/.cache/*.list
    else
            log "ERROR: rclone move to $ver: failed: $?"
    fi
else
    log "No local files found for Rclone to move"
fi

if [[ -d "/opt/plexguide/plex" ]]; then
    SECTION="PLEX CLEANUP"  
    plex_cleanup
fi

log "Sleeping for 2 mins"
sleep 2m

# Remove empty directories
find "$dlpath/downloads" -mindepth 2 -mmin +5 -type d -empty -delete
find "$dlpath/downloads" -mindepth 3 -mmin +360 -type d -size -100M -delete
find "$dlpath/move" -mindepth 2 -mmin +5 -type d -empty -delete
# CLEANUP WEEK OLD LIST FILES FROM CLOUD CACHE
find "$dlpath/gcrypt/.cache/" -type f -mtime +7 -name '*.list' -delete

done
