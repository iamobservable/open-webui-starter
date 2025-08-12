#!/bin/bash
# ERNI-KI Docling Load Test (up to 10MB)
# Рус: Нагрузочное тестирование Docling /v1/convert/file с файлами до 10MB

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

HOST="https://localhost"
ENDPOINT="$HOST/api/docling/v1/convert/file"
TARGET_SIZE_MB=${1:-10}

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Генерация тестового файла ~N MB (Markdown)
FILE="$TMP_DIR/big-${TARGET_SIZE_MB}MB.md"
python - <<PY > "$FILE"
import os, sys
mb = int(os.environ.get('TARGET', '10'))
chunk = ("# ERNI-KI Test Document\n\n" + ("Lorem ipsum dolor sit amet, consectetur adipiscing elit. " * 50) + "\n\n")
with open(sys.argv[1], 'w') as f:
    written = 0
    target = mb * 1024 * 1024
    while written < target:
        f.write(chunk)
        written += len(chunk.encode('utf-8'))
print(os.path.getsize(sys.argv[1]))
PY
TARGET=$TARGET_SIZE_MB python - "$FILE" >/dev/null

size_h=$(du -h "$FILE" | cut -f1)
echo -e "${BLUE}🚀 Docling load test: $size_h file → $ENDPOINT${NC}"

# Отправка с правильным полем multipart: files
start=$(date +%s%3N)
http_code=$(curl -sk -o /dev/null -w "%{http_code}" \
  -F "files=@$FILE;type=text/markdown" \
  -F "input_format=md" \
  -F "output_format=json_doctags" \
  "$ENDPOINT")
end=$(date +%s%3N)
duration=$((end - start))

if [ "$http_code" = "200" ]; then
  echo -e "${GREEN}✅ OK${NC} (${duration}ms for ~$size_h)"
  if [ $duration -le 5000 ]; then
    echo -e "${GREEN}✅ Requirement met: <5s${NC}"
  else
    echo -e "${YELLOW}⚠️ Exceeds 5s: ${duration}ms${NC} (проверить параметры pipeline/ресурсы)"
  fi
else
  echo -e "${RED}❌ HTTP $http_code${NC}"
  exit 1
fi

