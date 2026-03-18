#!/bin/bash
set -euo pipefail

sudo mkdir -p /etc/keyd
sudo tee /etc/keyd/default.conf > /dev/null << 'EOF'
[ids]

32ac:0012
32ac:0014

[main]

capslock = layer(control)
EOF

sudo systemctl enable --now keyd
sudo systemctl restart keyd
