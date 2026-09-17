#!/usr/bin/env bash
set -euo pipefail
cd /home/yingchaomu/下载/SUGAR

echo "[1/3] data.zip"
uvx --from gdown gdown 1AIJWqS5rFGl5u2Qq6jCCTHKdh51SX2Sc -O data.zip
unzip -q -o data.zip
rm data.zip

echo "[2/3] descriptions.zip"
uvx --from gdown gdown 1wXNAjNMrfV0e-d2pQ6m9dm4xrG5lSoyD -O descriptions.zip
unzip -q -o descriptions.zip
rm descriptions.zip

echo "[3/3] demo_ckpts.zip"
uvx --from gdown gdown 1Uc2SPPVvTboEgw4Scyuz3TmzNKDg-dx- -O demo_ckpts.zip
unzip -q -o demo_ckpts.zip
rm demo_ckpts.zip

echo "DONE: data download complete"
du -sh data descriptions demo_ckpts
