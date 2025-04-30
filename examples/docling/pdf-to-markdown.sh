#!/bin/env sh

curl -X POST "http://localhost:5001/v1alpha/convert/source" -H "accept: application/json" -H "Content-Type: application/json" -d @config.json
