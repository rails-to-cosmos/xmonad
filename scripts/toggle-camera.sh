#!/bin/sh
case "$1" in
    off)
        sudo modprobe -r uvcvideo
        echo "blacklist uvcvideo" | sudo tee /etc/modprobe.d/no-camera.conf >/dev/null
        echo "Camera disabled" ;;
    on)
        sudo rm -f /etc/modprobe.d/no-camera.conf
        sudo modprobe uvcvideo
        echo "Camera enabled" ;;
    *)
        if lsmod | grep -q uvcvideo; then echo "Camera: on"
        else echo "Camera: off"; fi ;;
esac
