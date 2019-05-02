#!/bin/bash

command -v git || pacman --noconfirm --sync --refresh git

if [ -d "/opt/ansible-scripts/.git" ]; then
    git -C /opt/ansible-scripts fetch origin
    git -C /opt/ansible-scripts reset --hard origin/$1
else
    git -C /opt clone https://github.com/auriusbendikas/ansible-scripts.git
    git -C /opt/ansible-scripts checkout $1
fi
