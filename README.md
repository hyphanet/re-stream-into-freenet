Stream to Freenet
=================


Re-Stream a live-stream as live-audio
-------------------------------------

Needs ffmpeg and `pip3 install --user pyFreenet3`.

Example with theradio.cc using an existing hyphanet node (install [from hyphanet.org](https://www.hyphanet.org):

    cd /tmp && \
    git clone https://github.com/hyphanet/re-stream-into-freenet && \
    re-stream-into-freenet/hyphastream-single-node.sh theradiocc \
      "http://ogg.theradio.cc/" $(((3 * 24 * 60 * 60))) \
      "The Radio.cc: theradio.cc"

It should just work.

Example with automatic setup of multiple hyphanet nodes:

    cd /tmp && \
    git clone https://github.com/hyphanet/re-stream-into-freenet && \
    cd re-stream-into-freenet && \
    echo -e "\n1\n" | ./re-stream-to-freenet.sh theradiocc \
      "http://ogg.theradio.cc/" $(((3 * 24 * 60 * 60))) \
      "The Radio.cc: theradio.cc"

Follow the prompts. The stream should get inserted with about 15 minutes delay.

[Streamlink](https://streamlink.github.io/) is a tool that reads the sites of known streaming sites and
returns a link that can be used from streaming software.


Notes on camera-input
---------------------

Get stream from webcam: https://trac.ffmpeg.org/wiki/Capture/Webcam#Linux
needs `guix install v4l-utils ffmpeg python` and `pip3 install --user pyFreenet3`.

Get stream formats:

    ffmpeg -f v4l2 -list_formats all -i /dev/video0

Record stream:

    ffmpeg -f v4l2 -input_format h264 -framerate 25 -video_size 320x180 -i /dev/video0 output.ogv

Split recorded stream: https://unix.stackexchange.com/questions/1670/how-can-i-use-ffmpeg-to-split-mpeg-video-into-10-minute-chunks

    mkdir output; ffmpeg -i /dev/video0 -f v4l2 -input_format h264 -framerate 25 -video_size 320x180 -map 0 -segment_time 00:00:10 -f segment -reset_timestamps 1 output/output%03d.mp4

Use Theora and Vorbis so the files survive the Freenet content filter:

    mkdir output; ffmpeg -f v4l2 -input_format h264 -framerate 25 -video_size 320x180 -i /dev/video0 -map 0 -segment_time 00:00:10 -c:v theora -c:a libvorbis -f segment -reset_timestamps 1 output/output%03d.ogv

