#!/bin/bash
set -euo pipefail

sudo mkdir -p /etc/keyd
sudo tee /etc/keyd/default.conf > /dev/null << 'EOF'
[ids]

*

[main]

capslock = leftcontrol
EOF

sudo systemctl enable --now keyd
sudo systemctl restart keyd
