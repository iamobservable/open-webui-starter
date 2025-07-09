#!/usr/bin/env bash

mkdir -p $HOME/bin
curl -s https://raw.githubusercontent.com/iamobservable/open-webui-starter/refs/heads/main/starter.sh > $HOME/bin/starter
chmod +x $HOME/bin/starter

echo "starter successfully installed in $HOME/bin"
