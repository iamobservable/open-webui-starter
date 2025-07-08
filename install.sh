#!/usr/bin/env bash

mkdir -p $HOME/bin
curl -s https://raw.githubusercontent.com/iamobservable/open-webui-starter/feature/iamobservable/64-convert-project-script-to-installable/starter.sh > $HOME/bin/starter
chmod +x $HOME/bin/starter

echo "starter successfully installed in $HOME/bin"
