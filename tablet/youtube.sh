#!/bin/sh
# YouTube for a 2014 tablet: search box, then the top result plays full-screen in mpv at 360p H.264
# (a browser can't keep up with YouTube on this CPU; mpv decodes 360p fine in software).
q="$1"
[ -z "$q" ] && q=$(zenity --entry --title="YouTube" --text="Search YouTube:" --width=520 2>/dev/null)
[ -z "$q" ] && exit 0
exec mpv --fs --hwdec=no --vo=xv,x11 --profile=sw-fast --cache=yes --demuxer-max-bytes=30MiB \
  --ytdl-format='bv*[height<=240][vcodec^=avc1]+ba/bv*[height<=360][vcodec^=avc1]+ba/b[height<=360]/wv*+ba' \
  --osd-level=1 --title="YouTube - %{media-title}" "ytdl://ytsearch1:$q"
