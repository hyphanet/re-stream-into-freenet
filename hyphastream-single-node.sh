#!/usr/bin/env bash
# re-stream-to-freenet.sh --- forward an existing live-stream into Freenet

# Copyright (C) 2022-2025 Dr. Arne Babenhauserheide <arne_bab@web.de>

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

VERSION=0.1
# export host and port: needed in subscripts
export HOST=127.0.0.1
export PORT=9481

while getopts -- dvhVH:P:-: OPT; do
  if [ "$OPT" = "-" ]; then
      OPT="$OPTARG" # replace opt by long opt
      LONG_OPTARG="${OPTARG#*=}"
  fi
  case "$OPT" in
    d | debug ) DEBUG=true ;;
    v | verbose ) VERBOSE=true ;;
    h | help ) HELP=true ;;
    V | version ) echo $VERSION; exit 0 ;;
    H ) HOST="$OPTARG" ;;
    host=?* ) HOST="$LONG_OPTARG" ;;
    P ) PORT="$OPTARG" ;;
    port=?* ) PORT="$LONG_OPTARG" ;;
    \? ) exit 2 ;; # illegal option
    * ) echo "unknown option --$OPTARG"; exit 2 ;;
  esac
done
shift $((OPTIND-1))

if ! test -z "$HELP" || test -z "$1" || test -z "$2" || test -z "$3" || test -z "$4"; then
    echo "usage: $0 [-d | --debug] [-v | --verbose] [-V | --version] <prefix> <streamlink> <streamtime-seconds> <title> [<secret key>]"
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


# TODO: only provide more output if debug

# Choose a prefix to use for the folder that will cache the audio-files
export FILEPREFIX="$1"
# Select the source: (any audio or video stream or download which ffmpeg can handle; it fails on opus.theradio.cc)
SOURCE="$2"
# Set the streamtime: (the maximum time this setup can do is 4 days)
STREAMTIME="$3"
TITLE="$4"
FREENET_NODES_BASEFOLDER=$(mktemp -d "/tmp/${FILEPREFIX}"XXXXXXXX)
cd "${FREENET_NODES_BASEFOLDER}"

# Extract chunks of audio from the stream

# first do 5 short segments so people can get in, then create larger segments in the background
rm -rf "${FREENET_NODES_BASEFOLDER}"/FREESTREAM-split/
mkdir "${FREENET_NODES_BASEFOLDER}"/FREESTREAM-split/
cd "${FREENET_NODES_BASEFOLDER}"/FREESTREAM-split/
echo === Starting to transcode in the background.
echo === You can watch the transcoding via tail -F "$(realpath nohup.out)"
DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "${SOURCE}" | grep N/A)
if [[ x"$DURATION" == x"N/A" ]]; then
    START_TIME_SECOND_STREAM=00:00:00
else
    START_TIME_SECOND_STREAM=00:02:30
fi
# 30 seconds are 150-300kiB, the ideal size for long-lived files in Freenet
(timeout 150 nohup ffmpeg -i "${SOURCE}"  \
        -c:a libvorbis -vn -map 0:a:0 \
        -b:a 48k \
        -segment_time 00:00:30 \
        -f segment \
        -reset_timestamps 1 "${FILEPREFIX}000%01d.ogg";
# echo === First 5 segments done.
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
         -reset_timestamps 1 "${FILEPREFIX}1%03d.ogg") &

# Generate keys and playlist

export KEY=$(fcpgenkey -H $HOST -P $PORT | tail -n 1)
PUBKEY=$(fcpinvertkey -H $HOST -P $PORT $KEY)
# use -- as number prefix for the first chunks that are smaller
for i in {0..4}; do
    echo "${FILEPREFIX}000${i}.ogg" >> stream.m3u;
done
for i in {000..999}; do
    echo "${FILEPREFIX}1${i}.ogg" >> stream.m3u;
done
# insert stream.m3u with high priority to ensure that it does not get
# drowned by later audio file inserts use the last node for the
# streaming file
fcpupload -H $HOST -P $PORT -e -p 2 ${KEY}stream.m3u stream.m3u >/dev/null 2>&1 
# provide the link to the playlist
echo === Streaming radio to ${PUBKEY}stream.m3u

# show how to actually provide the stream as a freesite

echo === Creating minimal streaming site:
# the passed key is only used for the freesite
INDEXKEY="$(echo ${5:-${KEY}} | sed s/^SSK@/USK@/)"
INDEXURI="${INDEXKEY}${FILEPREFIX}/-1/"
INDEXPUB="$(fcpinvertkey -H $HOST -P $PORT "${INDEXURI}")"
cat > index.html <<-EOF
    <!DOCTYPE html><html><head><meta charset="utf-8" /><title>Stream</title><style>body {background-color: silver}</style></head><body><h1>${TITLE}</h1><audio src="/${PUBKEY}stream.m3u" controls="controls" style="height: 40px" ></audio><p>Source: ${SOURCE}</p><p><a href="/?newbookmark=${INDEXPUB}&desc=${TITLE}&hasAnActivelink=false">Bookmark this site</a></p></body></html>
EOF
# use highest sane priority, because this insert to a USK also checks
# for the highest version and adds indexing metadata (date hints).
fcpupload -H $HOST -P $PORT -e -p 2 "${INDEXURI}index.html" "index.html"  >/dev/null 2>&1 &
echo http://${HOST}:8888/freenet:${INDEXPUB}
echo You can check whether the upload is done at ${HOST}:${PORT}/uploads/
echo To update the site, use this script again and pass it the secret key:
echo "    $0 '$1' '$2' '$3' '$4' '${INDEXKEY}'" >&2
echo
echo To use the stream on a freesite, just insert the following tag:
echo 'Stream: <audio src="/'${PUBKEY}stream.m3u'" controls="controls" style="height: 40px" ></audio>'

# Upload the streamfiles

for i in 000{0..4} 1{000..999}; do echo $i; done | \
    xargs -I {} -P 10 bash -c '
PRE="${FILEPREFIX}{}"
if [[ x"{}" == x"1999" ]]; then
  sleep 360 # wait one full segment for the last file
else
  # wait until the file to upload exists
  while ! ls | grep -q ${PRE}; do
    sleep 1
  done
  # then wait until the last file is no longer the file to upload
  while ls | grep ${PRE} -A1 | tail -n 1 | grep -q ${PRE}; do
    sleep 1
  done
fi
fcpupload -w -H $HOST -P $PORT -e -p 3 "${KEY}${PRE}.ogg" "${PRE}.ogg"
'
echo === All the files finished uploading. ===

