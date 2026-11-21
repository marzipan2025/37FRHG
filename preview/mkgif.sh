#!/bin/sh
# gif/<mode>NN.png → <mode>.gif + <mode>_sheet.png (8프레임). PIL 대신 ffmpeg.
m=${1:-custom}
ffmpeg -y -loglevel error -framerate 12 -i gif/${m}%02d.png -vf "scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse" -loop 0 $m.gif
ffmpeg -y -loglevel error -framerate 1 -i gif/${m}%02d.png -vf "select='not(mod(n\,3))',scale=600:-1,tile=2x4" -frames:v 1 ${m}_sheet.png
