# Troubleshooting ERNI-KI

- Начните с `docker compose ps`, `docker compose logs` и `docker compose top`.
- Используйте `docs/operations/handbook.md` и
  `docs/runbooks/troubleshooting-guide.md` для типовых сценариев.
- Проверяйте healthchecks (`curl -s http://localhost:PORT/metrics`).
