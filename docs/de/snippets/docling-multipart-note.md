# Hinweis: Docling /v1/convert/file – Multipart Feldname

– Für das Endpoint POST /v1/convert/file (Docling Serve) muss das Multipart-Feld zwingend "files" (Array) heißen, nicht "file". Andernfalls tritt ein HTTP 422 Fehler auf.

Beispiele:

– Korrekt:

curl -k -X POST \
  -F "files=@example.pdf" \
  -F "input_format=pdf" \
  -F "output_format=json_doctags" \
  https://<host>/api/docling/v1/convert/file

– Falsch (führt zu 422):

curl -k -X POST \
  -F "file=@example.pdf" \
  https://<host>/api/docling/v1/convert/file

// Deutschsprachiger Hinweis: Docling erwartet ein Array-Feld "files" für Uploads; mehrere Dateien werden unterstützt.
