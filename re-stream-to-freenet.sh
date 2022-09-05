#!/usr/bin/env bash
# re-stream-to-freenet.sh --- forward an existing live-stream into Freenet

# Copyright (C) 2022 Dr. Arne Babenhauserheide <arne_bab@web.de>

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


if test -z $1 || test -z $2 || test -z $3; then
    echo "usage: $0 <prefix> <streamlink> <streamtime-seconds>"
    echo
    echo "example: stream the Ian FUTO interview for 3 hours:"
    echo "    $0 futo-freenet "'"$(streamlink https://www.youtube.com/watch?v=eoV9amsnaQg 720p --stream-url)" $(((3 * 60 * 60)))'
    exit 1
fi

# stream the radio cc (without transcoding)
# Choose a prefix to use for the audio-files in Freenet
FILEPREFIX="$1"
# Select the source: (64k ogg)
SOURCE="$2"
# Set the streamtime: 3 days (the maximum time this setup can do is 4 days)
STREAMTIME="$3"
FREENET_NODES_BASEFOLDER=$(mktemp -d "/tmp/${FILEPREFIX}"XXXXXXXX)
mkdir "${FREENET_NODES_BASEFOLDER}"
cd "${FREENET_NODES_BASEFOLDER}"
# following https://www.draketo.de/software/install-freenet-linux.html
# use the Lysator mirror, because github throttles us
wget http://ftp.lysator.liu.se/pub/freenet/fred-releases/build01494/new_installer_offline_1494.jar \
  -O freenet-installer.jar
mkdir node1
cd node1
echo === 
echo follow the prompts
echo ===
java -jar ../freenet-installer.jar -console
./run.sh stop
# setting up default settings and restarting
cat > freenet.ini <<EOF
security-levels.networkThreatLevel=LOW
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
node.slashdotCacheSize=53687091
node.minDiskFreeShortTerm=536870912
node.uploadAllowedDirs=all
node.outputBandwidthLimit=131072
node.storeSize=429496730
node.storeType=ram
node.assumeNATed=true
node.clientCacheType=ram
node.l10n=English
node.inputBandwidthLimit=131072
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
    sed -i s/node.inputBandwidthLimit=.*/node.inputBandwidthLimit=70k/ node$i/freenet.ini
    sed -i s/node.outputBandwidthLimit=.*/node.outputBandwidthLimit=70k/ node$i/freenet.ini
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
echo === creating the first 10 segments, 5 minutes, before starting to upload.
echo === Please give them enough time.
rm -rf "${FREENET_NODES_BASEFOLDER}"/FREESTREAM-split/
mkdir "${FREENET_NODES_BASEFOLDER}"/FREESTREAM-split/
cd "${FREENET_NODES_BASEFOLDER}"/FREESTREAM-split/
# 30 seconds are 200-300kiB, the ideal size for long-lived files in Freenet
timeout 300 nohup ffmpeg -i "${SOURCE}"  \
        -c:a libvorbis -vn -map 0:a:0 \
        -b:a 48k \
        -segment_time 00:00:30 \
        -f segment \
        -reset_timestamps 1 "${FILEPREFIX}--%01d.ogg"
echo === First 10 segments done. Later segments are created in the background.
echo === This setup can live-stream radio for more than 4 days.
# 6 minutes segments are about 2.5MiB each, ensured below 4MiB, 
# the maximum size for single-container files in Freenet.
# This reduces the audible stops in the audio during streaming,
# and 6 minute segments are easy to track for humans,
# because 10 segments are one hour. This way we can create streams
# that you can step in at any hour of the day.
timeout ${STREAMTIME} nohup ffmpeg -i "${SOURCE}"  \
        -c:a libvorbis -vn -map 0:a:0 \
        -b:a 48k \
        -segment_time 00:06:00 \
        -f segment \
        -reset_timestamps 1 "${FILEPREFIX}%03d.ogg" &

KEY=$(fcpgenkey -P 9180 | tail -n 1)
PUBKEY=$(fcpinvertkey -P 9180 $KEY)
for i in {0..9}; do
    echo "${FILEPREFIX}--${i}.ogg" >> stream.m3u;
done
for i in {000..999}; do
    echo "${FILEPREFIX}${i}.ogg" >> stream.m3u;
done
# insert stream.m3u with compression because it is large and very
# repetitive, and with high priority to ensure that it does not get
# drowned by later mp3 inserts
# use the last node for the streaming file
fcpupload -P 9580 -p 2 ${KEY}stream.m3u stream.m3u
# provide the link to the playlist
echo === Streaming radio to $(fcpinvertkey -P 9180 $KEY)stream.m3u

# show how to actually provide the stream as a freesite

echo ===
echo To create a streaming site, open the Sharesite plugin site
echo http://localhost:8180/Sharesite/ 
echo in your browser, click "create a new freesite"
echo open your freesite and enter the following:
echo 'Stream: <audio src="/'$(fcpinvertkey -P 9180 $KEY)stream.m3u'" controls="controls" style="height: 40px" ></audio>'
echo Then change the Insert Hour to -1 to insert at once.
echo Save it, go back to the freesite menu, then tick its checkbox and click insert.
echo Once a link appears next to your site, your streaming page is ready. You can use that link to share it.
echo ===
echo mpv --ytdl=no --prefetch-playlist http://127.0.0.1:8888/freenet:$(fcpinvertkey -P 9180 $KEY)stream.m3u
for i in -- {00..99}; do
    # upload 9 files in parallel, because Freenet does some checking
    # for availability, that does not consume much bandwidth but takes
    # time
    PRE="${FILEPREFIX}${i}"
    # wait until the next file is available, to ensure that the current file is ready
    while test ! -e "${PRE}1.ogg"; do sleep 10; done
    date # for statistics
    # upload the first 5 files, one file per insertion-node
    # the first 5 get higher priority
    fcpupload -P 9180 -p 2 "${KEY}${PRE}0.ogg" "${PRE}0.ogg"
    while test ! -e "${PRE}2.ogg"; do sleep 10; done
    fcpupload -P 9280 -p 2 "${KEY}${PRE}1.ogg" "${PRE}1.ogg"
    while test ! -e "${PRE}3.ogg"; do sleep 10; done
    fcpupload -P 9380 -p 2 "${KEY}${PRE}2.ogg" "${PRE}2.ogg"
    while test ! -e "${PRE}4.ogg"; do sleep 10; done
    fcpupload -P 9480 -p 2 "${KEY}${PRE}3.ogg" "${PRE}3.ogg"
    while test ! -e "${PRE}5.ogg"; do sleep 10; done
    fcpupload -P 9580 -p 2 "${KEY}${PRE}4.ogg" "${PRE}4.ogg"
    # the next 5 get lower priority so the first finish earlier, 
    # but they run in parallel to catch up on time lost at the end
    while test ! -e "${PRE}6.ogg"; do sleep 10; done
    fcpupload -P 9180 "${KEY}${PRE}5.ogg" "${PRE}5.ogg" &
    while test ! -e "${PRE}7.ogg"; do sleep 10; done
    fcpupload -P 9280 "${KEY}${PRE}6.ogg" "${PRE}6.ogg" &
    while test ! -e "${PRE}8.ogg"; do sleep 10; done
    fcpupload -P 9380 "${KEY}${PRE}7.ogg" "${PRE}7.ogg" &
    while test ! -e "${PRE}9.ogg"; do sleep 10; done
    # wait for completion of the upload before the last upload 
    # as a primitive way to limit parallelism; 
    # no use clogging the node if it cannot keep up
    fcpupload -w -P 9480 "${KEY}${PRE}8.ogg" "${PRE}8.ogg"
    # wait a full segment to ensure that the last file actually is ready
    # (because we do not have the next key yet, so we cannot do nice checking)
    sleep 360
    fcpupload -P 9580 "${KEY}${PRE}9.ogg" "${PRE}9.ogg"
done
sleep 300
echo === All the files finished uploading. Stopping the streaming nodes.
for i in "${FREENET_NODES_BASEFOLDER}"/node*; do cd $i; ./run.sh stop; cd -; done
