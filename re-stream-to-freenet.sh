#!/usr/bin/env bash
# re-stream-to-freenet.sh --- forward an existing live-stream into Freenet

# Copyright (C) 2022-2024 Dr. Arne Babenhauserheide <arne_bab@web.de>

# Author: Dr. Arne Babenhauserheide <arne_bab@web.de>

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.


if test -z $1 || test -z $2 || test -z $3 || test -z $4; then
    echo "usage: $0 <prefix> <streamlink> <streamtime-seconds> <title> [<secret key>]"
    echo
    echo "The secret key must be an SSK and must end with a slash (/). It is only used for the auto-generated streaming-page."
    echo
    echo "examples:"
    echo
    echo "stream The Radio.cc for 3 days: https://theradio.cc/"
    echo "    $0 theradiocc "'"http://ogg.theradio.cc/" $(((3 * 24 * 60 * 60))) "The Radio.cc: theradio.cc"'
    echo
    echo "stream 37c3 PSYOPS: https://media.ccc.de/v/37c3-12326-you_ve_just_been_fucked_by_psyops"
    echo "    $0 37c3-psyops "'"https://cdn.media.ccc.de/congress/2023/h264-sd/37c3-12326-eng-deu-YOUVE_JUST_BEEN_FUCKED_BY_PSYOPS_sd.mp4" $(((1 * 60 * 60))) "Stream PSYOPS: media.ccc.de/v/37c3-12326-you_ve_just_been_fucked_by_psyops"'
    echo
    echo "stream open culture for beginners:"
    echo "    $0 openculture-ccby "'"$(streamlink https://www.youtube.com/watch?v=y3vV-yvMfF0 360p --stream-url)" $(((1 * 60 * 60))) "Open Culture Webinar: youtube.com/watch?v=y3vV-yvMfF0"'
    exit 1
fi

# Choose a prefix to use for the folder that will cache the audio-files
FILEPREFIX="$1"
# Select the source: (any audio or video stream or download which ffmpeg can handle; it fails on opus.theradio.cc)
SOURCE="$2"
# Set the streamtime: (the maximum time this setup can do is 4 days)
STREAMTIME="$3"
TITLE="$4"
FREENET_NODES_BASEFOLDER=$(mktemp -d "/tmp/${FILEPREFIX}"XXXXXXXX)
cd "${FREENET_NODES_BASEFOLDER}"
# following https://www.draketo.de/software/install-freenet-linux.html
# use the Lysator mirror, because github throttles us
wget http://ftp.lysator.liu.se/pub/freenet/fred-releases/build01497/new_installer_offline_1497.jar \
  -O freenet-installer.jar
mkdir node1
cd node1
echo === 
echo follow the prompts
echo ===
echo 1 | java -jar ../freenet-installer.jar -console
./run.sh stop
# setting up default settings and restarting
cat > freenet.ini <<EOF
security-levels.networkThreatLevel=NORMAL
security-levels.physicalThreatLevel=NORMAL
fproxy.enableCachingForChkAndSskKeys=true
fproxy.hasCompletedWizard=true
fproxy.ssl=false
fproxy.enabled=true
fproxy.port=8180
logger.maxZippedLogsSize=1048
logger.priority=ERROR
pluginmanager.loadplugin=Sharesite
pluginmanager.enabled=true
node.slashdotCacheSize=10m
node.minDiskFreeShortTerm=200m
node.uploadAllowedDirs=all
node.inputBandwidthLimit=80k
node.outputBandwidthLimit=80k
node.storeSize=100m
node.storeType=ram
node.assumeNATed=true
node.clientCacheType=ram
node.l10n=English
fcp.port=9180
node.opennet.enabled=true
node.load.subMaxPingTime=7000
node.load.maxPingTime=15000
End
EOF
./run.sh restart
echo === giving Freenet some time to start
sleep 10
echo === stopping the node to replicate it
./run.sh stop
cd "${FREENET_NODES_BASEFOLDER}"
# Next just copy the folder:
for i in {2..5}; do cp -r node1 node$i; done
# Then remove the listen-port lines in freenet.ini. This causes
# Freenet to create unique listen ports on the next run.
# Also adjust the fcpport, fred port, and the bandwidth
for i in {1..5}; do
    sed -i s/fproxy.port=.*/fproxy.port=8${i}80/  node$i/freenet.ini
    sed -i s/fcp.port=.*/fcp.port=9${i}80/  node$i/freenet.ini
    sed -i s/node.listenPort=.*// node$i/freenet.ini
    sed -i s/node.opennet.listenPort=.*// node$i/freenet.ini
    sed -i s/node.inputBandwidthLimit=.*/node.inputBandwidthLimit=80k/ node$i/freenet.ini
    sed -i s/node.outputBandwidthLimit=.*/node.outputBandwidthLimit=80k/ node$i/freenet.ini
done
# And start them:
for i in {1..5}; do cd node$i; ./run.sh start; cd -; done
# check the settings.
grep -i \\.port node*/*ini
# expected:
# node1/freenet.ini:fproxy.port=8180
# node1/freenet.ini:fcp.port=9180
# node2/freenet.ini:fproxy.port=8280
# node2/freenet.ini:fcp.port=9280
# node3/freenet.ini:fproxy.port=8380
# node3/freenet.ini:fcp.port=9380
# node4/freenet.ini:fproxy.port=8480
# node4/freenet.ini:fcp.port=9480
# node5/freenet.ini:fproxy.port=8580
# node5/freenet.ini:fcp.port=9580
# Now we have 5 running nodes on FCP ports 9180 to 9580. We‘ll use them to insert

# copy ogg data from theradio.cc
# first do 10 short segments so people can get in, then create larger segments in the background
rm -rf "${FREENET_NODES_BASEFOLDER}"/FREESTREAM-split/
mkdir "${FREENET_NODES_BASEFOLDER}"/FREESTREAM-split/
cd "${FREENET_NODES_BASEFOLDER}"/FREESTREAM-split/
echo === Starting to transcode in the background.
echo === You can watch the transcoding via tail -F "$(realpath nohup.out)"
DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "${SOURCE}" | grep N/A)
if [[ x"$DURATION" == x"N/A" ]]; then
    START_TIME_SECOND_STREAM=00:00:00
else
    START_TIME_SECOND_STREAM=00:05:00
fi
# 30 seconds are 150-300kiB, the ideal size for long-lived files in Freenet
(timeout 300 nohup ffmpeg -i "${SOURCE}"  \
        -c:a libvorbis -vn -map 0:a:0 \
        -b:a 48k \
        -segment_time 00:00:30 \
        -f segment \
        -reset_timestamps 1 "${FILEPREFIX}--%01d.ogg";
# echo === First 10 segments done. Later segments are created in the background.
# echo === This setup can live-stream radio for more than 4 days.
# 6 minutes segments are about 2.5MiB each, ensured below 4MiB, 
# the maximum size for single-container files in Freenet.
# This reduces the audible stops in the audio during streaming,
# and 6 minute segments are easy to track for humans,
# because 10 segments are one hour. This way we can create streams
# that you can step in at any hour of the day.
 timeout ${STREAMTIME} nohup ffmpeg -i "${SOURCE}" \
         -ss ${START_TIME_SECOND_STREAM} \
         -c:a libvorbis -vn -map 0:a:0 \
         -b:a 48k \
         -segment_time 00:06:00 \
         -f segment \
         -reset_timestamps 1 "${FILEPREFIX}%03d.ogg") &

KEY=$(fcpgenkey -P 9180 | tail -n 1)
PUBKEY=$(fcpinvertkey -P 9180 $KEY)
for i in {0..9}; do
    echo "${FILEPREFIX}--${i}.ogg" >> stream.m3u;
done
for i in {000..999}; do
    echo "${FILEPREFIX}${i}.ogg" >> stream.m3u;
done
# insert stream.m3u with high priority to ensure that it does not get
# drowned by later audio file inserts use the last node for the
# streaming file
fcpupload -P 9580 -e -p 2 ${KEY}stream.m3u stream.m3u >/dev/null 2>&1 
# provide the link to the playlist
echo === Streaming radio to ${PUBKEY}stream.m3u

# show how to actually provide the stream as a freesite

echo ===
echo Creating minimal streaming site:
# the passed key is only used for the freesite
INDEXKEY="$(echo ${5:-${KEY}} | sed s/^SSK@/USK@/)"
INDEXURI="${INDEXKEY}${FILEPREFIX}/0/"
INDEXPUB="$(fcpinvertkey -P 9180 "${INDEXURI}")"
cat > index.html <<-EOF
    <!DOCTYPE html><html><head><meta charset="utf-8" /><title>Stream</title><style>body {background-color: silver}</style></head><body><h1>${TITLE}</h1><audio src="/${PUBKEY}stream.m3u" controls="controls" style="height: 40px" ></audio><p>Source: ${SOURCE}</p><p><a href="/?newbookmark=${INDEXPUB}&desc=${TITLE}&hasAnActivelink=false">Bookmark this site</a></p></body></html>
EOF
# use highest sane priority, because this insert to a USK also checks
# for the highest version and adds indexing metadata (date hints).
fcpupload -P 9580 -e -p 2 "${INDEXURI}index.html" "index.html"  >/dev/null 2>&1 &
echo http://127.0.0.1:8580/freenet:${INDEXPUB}
echo You can check whether the upload is done at http://127.0.0.1:8580/uploads/
echo To update the site, use this script again and pass it the secret key:
echo "    $0 '$1' '$2' '$3' '$4' '${INDEXKEY}'" >&2
echo
# echo ===
# echo To create a streaming site with additional content, open the Sharesite plugin site
# echo http://localhost:8180/Sharesite/
# echo in your browser, click "create a new freesite"
# echo open your freesite and enter the following:
echo To use the stream on a freesite, just insert the following tag:
echo 'Stream: <audio src="/'${PUBKEY}stream.m3u'" controls="controls" style="height: 40px" ></audio>'
# echo Then change the Insert Hour to -1 to insert at once.
# echo Save it, go back to the freesite menu, then tick its checkbox and click insert.
# echo Once a link appears next to your site, your streaming page is ready. You can use that link to share it.
# echo ===
# echo mpv --ytdl=no --prefetch-playlist http://127.0.0.1:8888/freenet:${PUBKEY}stream.m3u
for i in -- {00..99}; do
    # upload 9 files in parallel, because Freenet does some checking
    # for availability, that does not consume much bandwidth but takes
    # time
    PRE="${FILEPREFIX}${i}"
    # wait until the next file is available, to ensure that the current file is ready
    while test ! -e "${PRE}1.ogg"; do sleep 10; done
    date # for statistics
    # upload the first 5 files, one file per insertion-node
    # the first 5 get higher priority to ensure they finish earlier
    fcpupload -P 9180 -e -p 3 "${KEY}${PRE}0.ogg" "${PRE}0.ogg"
    while test ! -e "${PRE}2.ogg"; do sleep 10; done
    fcpupload -P 9280 -e -p 3 "${KEY}${PRE}1.ogg" "${PRE}1.ogg" 2>/dev/null
    while test ! -e "${PRE}3.ogg"; do sleep 10; done
    fcpupload -P 9380 -e -p 3 "${KEY}${PRE}2.ogg" "${PRE}2.ogg" 2>/dev/null
    while test ! -e "${PRE}4.ogg"; do sleep 10; done
    fcpupload -P 9480 -e -p 3 "${KEY}${PRE}3.ogg" "${PRE}3.ogg" 2>/dev/null
    while test ! -e "${PRE}5.ogg"; do sleep 10; done
    fcpupload -P 9580 -e -p 3 "${KEY}${PRE}4.ogg" "${PRE}4.ogg" 2>/dev/null
    # the next 5 get lower priority so the first finish earlier, 
    # but they run in parallel to catch up on time lost on the
    # last blocks (multi-insert of the top key)
    while test ! -e "${PRE}6.ogg"; do sleep 10; done
    fcpupload -P 9180 -e -p 4 "${KEY}${PRE}5.ogg" "${PRE}5.ogg" 2>/dev/null
    while test ! -e "${PRE}7.ogg"; do sleep 10; done
    fcpupload -P 9280 -e -p 4 "${KEY}${PRE}6.ogg" "${PRE}6.ogg" 2>/dev/null
    while test ! -e "${PRE}8.ogg"; do sleep 10; done
    fcpupload -P 9380 -e -p 4 "${KEY}${PRE}7.ogg" "${PRE}7.ogg" 2>/dev/null
    while test ! -e "${PRE}9.ogg"; do sleep 10; done
    fcpupload -P 9480 -e -p 4 "${KEY}${PRE}8.ogg" "${PRE}8.ogg" 2>/dev/null
    # Wait for the expected next key. This uses kind of brittle math
    # on the loop variable, but avoids doing more complex trickery.
    if [[ x"$i" == x"--" ]]; then
        while test ! -e "${FILEPREFIX}000.ogg"; do sleep 10; done
    elif [[ x"${i}" == x"99" ]]; then
        # this is the last iteration. Wait one full segment to ensure
        # that the last file is ready.
        sleep 360 # 6 minutes
    elif test "${i}" -lt 9; then
        # Must force decimal base via 10#${i}, otherwise bash math
        # uses octal base for numbers starting with 0.
        while test ! -e "${FILEPREFIX}0$((10#${i} + 1))0.ogg"; do sleep 10; done
    else
        while test ! -e "${FILEPREFIX}$((${i} + 1))0.ogg"; do sleep 10; done
    fi
    # wait for completion of the last upload
    # as a primitive way to limit parallelism; 
    # no use clogging the node if it cannot keep up
    fcpupload -w -P 9580 -e -p 4 "${KEY}${PRE}9.ogg" "${PRE}9.ogg" 2>/dev/null
done
sleep 300
echo === All the files finished uploading. Stopping the streaming nodes.
for i in "${FREENET_NODES_BASEFOLDER}"/node*; do cd $i; ./run.sh stop; cd -; done
