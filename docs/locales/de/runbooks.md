# Runbooks & Troubleshooting (DE)

Zusammenfassung der wichtigsten Runbooks (englische Originale in
`docs/operations/runbooks/`):

| Thema                 | Referenzdatei (EN)                                    | Hinweis (DE)                                                               |
| --------------------- | ----------------------------------------------------- | -------------------------------------------------------------------------- |
| Backup & Restore      | `operations/runbooks/backup-restore-procedures.md`    | PostgreSQL + Backrest Wiederherstellung, Validation-Schritte enthalten.    |
| Service Restart       | `operations/runbooks/service-restart-procedures.md`   | Sicheres Neustarten einzelner Container mit Healthchecks.                  |
| Docling Shared Volume | `operations/runbooks/docling-shared-volume.md`        | Reinigung des Docling Upload-Volumes + Rechtefix.                          |
| Troubleshooting       | `operations/runbooks/troubleshooting-guide.md`        | Häufige Fehler (GPU, Redis, RAG) inkl. Befehle `docker logs`/`nvidia-smi`. |
| Configuration Changes | `operations/runbooks/configuration-change-process.md` | Genehmigter Prozess für Änderungen an Config/Compose.                      |

> Für laufende Vorfälle siehe auch `docs/archive/incidents/README.md` und die
> entsprechenden Berichte (Phase 1/2 usw.). Archon Tasks sollten alle Schritte
> spiegeln.
