#!/usr/bin/env bash

curl -X POST "http://localhost:5050/v1/audio/speech" -H "Content-Type: application/json" -H "Authorization: Bearer your_api_key_here" -d @examples/edgetts/alonso-es-hola.json > alonso-es-hola.mp3
