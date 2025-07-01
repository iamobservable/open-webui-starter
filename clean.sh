#!/usr/bin/env bash

echo
echo Shutting down and removing containers
docker compose down -v

echo
echo Removing environment files
rm -fv env/*.env

echo
echo Removing mcp configuration
rm -fv conf/mcp/config.json

echo
echo Removing compose file
rm -fv compose.yml
