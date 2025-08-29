#!/bin/bash
# Ручная проверка SSL сертификатов ERNI-KI

cd "$(dirname "$0")/../.."
./scripts/ssl/monitor-certificates.sh check
