docker run \
    -v /mnt/d/SynologyDrive/IHRC/work/Pulsenet/tostadas/pn_tostadas_container/mountdir:/inputs \
    -v /mnt/d/SynologyDrive/IHRC/work/Pulsenet/tostadas/pn_tostadas_container/update_sub_test:/outputs \
    --privileged \
    --cpus=4 \
    -ti \
    alancollins/pn2-tostadas:latest \
    /bin/bash
