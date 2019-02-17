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
library_root="/home/plex/media"
plex_media_scanner_cmd="export LD_LIBRARY_PATH=/usr/lib/plexmediaserver/lib; export PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR=/config/Library/Application\ Support; /usr/lib/plexmediaserver/Plex\ Media\ Scanner"
# Outside Variables
dlpath=$(cat /var/plexguide/server.hd.path)
ver=$(cat /var/plexguide/rclone/deploy.version)
. "$dlpath/gcrypt/.config/cloud/pgcloud.conf"
. "$dlpath/gcrypt/.config/bin/pgcloud.sh"

sleep 10
while true
do

SECTION="MOVE"
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

SECTION="SCAN"
readarray -t LOCALFILES < <(find "$dlpath/move/" -mindepth 1 -type f -cmin +0.233 -not -newerct "$START" -not -iname '*.partial~' -not -iname '*_HIDDEN~' -not -iname '*.QTFS' -not -iname '*unionfs-.fuse*' -not -iname '*unionfs*' -not -iname '*.DS_STORE')
log "${#LOCALFILES[@]} local file/s found for Plex Media Scanner"
if [[ -n $LOCALFILES ]]; then
	# Create empty array
	MEDIAFOLDERS=()
	for LOCALFILE in "${LOCALFILES[@]}" #Populate array with paths to plex library folders
	do
		LOCALFILESHORTNAME="$(echo "$LOCALFILE" | sed -e s@$dlpath/move/@@)"
		echo "$LOCALFILESHORTNAME" >> ${HOME}/.cache/$TIMESTAMP-files-from.list
		log "Adding ""$library_root/$(dirname "$LOCALFILESHORTNAME")"" to scanner array"
		MEDIAFOLDERS+=("$library_root/$(dirname "$LOCALFILESHORTNAME")")
	done
	readarray -t MEDIAFOLDERS < <(printf "%s\n" "${MEDIAFOLDERS[@]}" | sort -u)
	log "${#MEDIAFOLDERS[@]} Unique folder/s found for Plex Media Scanner"
		for MEDIAFOLDER in "${MEDIAFOLDERS[@]}"
		do
			case $MEDIAFOLDER in
			*/AudioBooks/*)
				log "EXECUTE Plex Media Scanner for folder $MEDIAFOLDER"
				docker exec -d plex /bin/bash -c "$plex_media_scanner_cmd --scan --refresh --section 6 --directory '${MEDIAFOLDER}'"
			;;
			*/eBooks/*)
				log "Skip scanning folder $MEDIAFOLDER"
				continue
			;;
			*/Comics/*)
				log "Skip scanning folder $MEDIAFOLDER"
				continue
			;;
			*/Movies/*)
				log "EXECUTE Plex Media Scanner for folder $MEDIAFOLDER"
				docker exec -d plex /bin/bash -c "$plex_media_scanner_cmd --scan --refresh --section 1 --directory '${MEDIAFOLDER}'"
			;;
			*/Music/*)
				log "EXECUTE Plex Media Scanner for folder $MEDIAFOLDER"
				docker exec -d plex /bin/bash -c "$plex_media_scanner_cmd --scan --refresh --section 3 --directory '${MEDIAFOLDER}'"
			;;
			*/Photos/*)
				log "EXECUTE Plex Media Scanner for folder $MEDIAFOLDER."
				docker exec -d plex /bin/bash -c "$plex_media_scanner_cmd --scan --refresh --section 7 --directory '${MEDIAFOLDER}'"
			;;
			*/Television/*)
				log "EXECUTE Plex Media Scanner for folder $MEDIAFOLDER"
				docker exec -d plex /bin/bash -c "$plex_media_scanner_cmd --scan --refresh --section 2 --directory '${MEDIAFOLDER}'"
			;;
			*)
				log "Skip scanning folder $MEDIAFOLDER"
				continue
			;;
		esac
		if [ $? -eq 0 ]; then
			log "SUCCESS: Plex Media Scanner"
		else
			log "ERROR: Plex Media Scanner ERROR: $?"
			#exit 1
		fi
	done

fi

SECTION="UPLD"
if [ -f ${HOME}/.cache/$TIMESTAMP-files-from.list ]; then
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

	cat ${HOME}/.cache/*-files-from.list > $dlpath/gcrypt/.cache/$TIMESTAMP-files-to.list
	rm ${HOME}/.cache/$TIMESTAMP-files-from.list
fi

SECTION="CLUP"
plex_cleanup

sleep 2m

# Remove empty directories
find "$dlpath/downloads" -mindepth 2 -mmin +5 -type d -empty -delete
find "$dlpath/downloads" -mindepth 3 -mmin +360 -type d -size -100M -delete
find "$dlpath/move" -mindepth 2 -mmin +5 -type d -empty -delete

done
