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
sleep 10

while true
do
STARTLOOP=$(date)
TIMESTAMP=`date +%Y-%m-%d_%H-%M-%S`
SECTION="MOVETO"
dlpath=$(cat /var/plexguide/server.hd.path)
## Sync, Sleep 2 Minutes, Repeat. BWLIMIT 9 Prevents Google 750GB Google Upload Ban
rclone moveto "$dlpath/downloads/" "$dlpath/move/" \
--config /opt/appdata/plexguide/rclone.conf \
--log-file=/var/plexguide/logs/pgmove.log \
--log-level INFO --stats 5s \
--min-age=2m \
--exclude="**_HIDDEN~" --exclude=".unionfs/**" \
--exclude='**partial~' --exclude=".unionfs-fuse/**" \
--exclude="**sabnzbd**" --exclude="**nzbget**" \
--exclude="**qbittorrent**" --exclude="**rutorrent**" \
--exclude="**deluge**" --exclude="**transmission**" \
--exclude="**jdownloader**" --exclude="**makemkv**" \
--exclude="**handbrake**" --exclude="**bazarr**" \
--exclude="**ignore**"  --exclude="**inProgress**" \
--exclude=".*"
if [[ $? -eq 0 ]]; then
        log "SUCCESS: rclone moveto to $dlpath/move/"
else
        log "ERROR: rclone moveto to $dlpath/move/ failed: $?"
fi

SECTION="PLEX MEDIA SCANNER"

while [ $(docker inspect -f '{{.State.Running}}' plex) = "false" ]; do
	log "Plex Container Not Running, sleeping 10 minutes"
	sleep 10m
done
log "Plex Container Running"

readarray -t LOCALFILES < <(find "$dlpath/move/" -mindepth 1 -type f -cmin +0.233 -not -newerct "$STARTLOOP" -not -iname '*.partial~' -not -iname '*_HIDDEN~' -not -iname '*.QTFS' -not -iname '*unionfs-.fuse*' -not -iname '*unionfs*' -not -iname '*.DS_STORE')
if [[ -n $LOCALFILES ]]; then
        log "${#LOCALFILES[@]} local file/s found for Plex Media Scanner"
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
			else
                        	log "ERROR: Error executing Plex Media Scanner ERROR: $?"
			fi
		elif [[ -z ${!section_varname} ]]; then
			log "SKIP: No existing Plex Media Library Section found for media folder $MEDIAFOLDER"
                elif [[ ! -d "$(echo $MEDIAFOLDER | sed -e s@$mediadir@$libraryroot@)" ]]; then
			log "SKIP: Plex Media Library folder $MEDIAFOLDER not found for scanner"
                fi
        done

        SECTION="RCLONE MOVE"
        log "Moving ${#LOCALFILES[@]} local file/s to $ver:/"
        rclone move "$dlpath/move/" "$ver:/" \
        --config /opt/appdata/plexguide/rclone.conf \
        --log-file=/var/plexguide/logs/pgmove.log \
        --log-level INFO --stats 5s \
        --files-from=${HOME}/.cache/$TIMESTAMP-files-from.list \
        --bwlimit 9M \
        --tpslimit 6 \
        --checkers=16 \
        --max-size=300G \
        --no-traverse
        if [[ $? -eq 0 ]]; then
                log "SUCCESS: rclone move to $ver:"
        else
                log "ERROR: rclone move to $ver: failed: $?"
        fi
        cat ${HOME}/.cache/*.list > $dlpath/gcrypt/.cache/$TIMESTAMP-files-to.list
        rm ${HOME}/.cache/*.list
	# CLEANUP WEEK OLD LIST FILES
	find "$dlpath/gcrypt/.cache/" -type f -mtime +7 -name '*.list' -execdir rm -- '{}' \;
fi

SECTION="PLEX CLEANUP"
plex_cleanup

log "Sleeping for 2 mins"
sleep 2m

# Remove empty directories
find "$dlpath/downloads" -mindepth 2 -mmin +5 -type d -empty -delete
find "$dlpath/downloads" -mindepth 3 -mmin +360 -type d -size -100M -delete
find "$dlpath/move" -mindepth 2 -mmin +5 -type d -empty -delete
done
