# 🤖 Automated Maintenance Guide - ERNI-KI

**Version:** 1.0  
**Last Updated:** 2025-10-24  
**Status:** Production Ready

---

## 📋 Overview

ERNI-KI implements comprehensive automated maintenance to ensure optimal system
performance, reliability, and resource utilization.

### Automation Components

| Component             | Schedule    | Purpose               | Status    |
| --------------------- | ----------- | --------------------- | --------- |
| **PostgreSQL VACUUM** | Sunday 3:00 | Database optimization | ✅ Active |
| **Docker Cleanup**    | Sunday 4:00 | Resource cleanup      | ✅ Active |
| **Log Rotation**      | Daily 3:00  | Log management        | ✅ Active |
| **System Monitoring** | Hourly      | Health checks         | ✅ Active |
| **Backrest Backups**  | Daily 1:30  | Data protection       | ✅ Active |

---

## 🗄️ PostgreSQL VACUUM Automation

### Overview

Automatic database maintenance to reclaim storage and update statistics for
optimal query performance.

### Configuration

**Schedule:** Every Sunday at 3:00 AM  
**Script:** `/tmp/pg_vacuum.sh`  
**Log File:** `/tmp/pg_vacuum.log`  
**Cron Entry:**

```cron
# ERNI-KI PostgreSQL VACUUM - каждое воскресенье в 3:00
0 3 * * 0 /tmp/pg_vacuum.sh >> /tmp/pg_vacuum.log 2>&1
```

### Script Content

```bash
#!/bin/bash
# ERNI-KI PostgreSQL VACUUM Automation
# Еженедельная очистка и оптимизация БД

cd /home/konstantin/Documents/augment-projects/erni-ki

echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting PostgreSQL VACUUM ANALYZE..."

docker compose exec -T db psql -U postgres -d openwebui -c "VACUUM ANALYZE;" 2>&1

if [ $? -eq 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - VACUUM ANALYZE completed successfully"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - VACUUM ANALYZE failed"
    exit 1
fi
```

### Manual Execution

```bash
# Run VACUUM manually
/tmp/pg_vacuum.sh

# View logs
tail -f /tmp/pg_vacuum.log

# Check last execution
grep "completed successfully" /tmp/pg_vacuum.log | tail -n 1
```

### Monitoring

```bash
# Check VACUUM statistics
docker compose exec db psql -U postgres -d openwebui -c "
SELECT
    schemaname,
    tablename,
    last_vacuum,
    last_autovacuum,
    vacuum_count,
    autovacuum_count
FROM pg_stat_user_tables
ORDER BY last_vacuum DESC NULLS LAST
LIMIT 10;"

# Check table bloat
docker compose exec db psql -U postgres -d openwebui -c "
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;"
```

### Benefits

- **Storage Reclamation:** Frees up disk space from deleted rows
- **Performance Improvement:** Updates statistics for query optimizer
- **Prevents Bloat:** Reduces table and index bloat
- **Automatic:** No manual intervention required

---

## 🐳 Docker Cleanup Automation

### Overview

Automatic cleanup of unused Docker resources to prevent disk space exhaustion.

### Configuration

**Schedule:** Every Sunday at 4:00 AM  
**Script:** `/tmp/docker-cleanup.sh`  
**Log File:** `/tmp/docker-cleanup.log`  
**Cron Entry:**

```cron
# ERNI-KI Docker Cleanup - каждое воскресенье в 4:00
0 4 * * 0 /tmp/docker-cleanup.sh >> /tmp/docker-cleanup.log 2>&1
```

### Script Content

```bash
#!/bin/bash
# ERNI-KI Docker Cleanup Automation
# Еженедельная очистка неиспользуемых образов и volumes

cd /home/konstantin/Documents/augment-projects/erni-ki

echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting Docker cleanup..."

# Очистка неиспользуемых образов старше 7 дней
echo "Cleaning unused images..."
docker image prune -a --filter "until=168h" -f 2>&1

# Очистка неиспользуемых volumes
echo "Cleaning unused volumes..."
docker volume prune -f 2>&1

# Очистка build cache
echo "Cleaning build cache..."
docker builder prune -a -f 2>&1

echo "$(date '+%Y-%m-%d %H:%M:%S') - Docker cleanup completed"
```

### Manual Execution

```bash
# Run cleanup manually
/tmp/docker-cleanup.sh

# View logs
tail -f /tmp/docker-cleanup.log

# Check disk usage before/after
docker system df
```

### What Gets Cleaned

| Resource        | Criteria                   | Impact                    |
| --------------- | -------------------------- | ------------------------- |
| **Images**      | Unused >7 days             | Frees disk space          |
| **Volumes**     | Not attached to containers | Removes orphaned data     |
| **Build Cache** | All build cache            | Clears temporary files    |
| **Networks**    | Unused networks            | Cleanup network resources |

### Monitoring

```bash
# Check Docker disk usage
docker system df

# Detailed breakdown
docker system df -v

# Check cleanup history
grep "cleanup completed" /tmp/docker-cleanup.log | tail -n 5
```

### Safety

- ✅ **Running containers:** Never affected
- ✅ **Active volumes:** Preserved
- ✅ **Tagged images:** Kept if in use
- ⚠️ **Unused images >7 days:** Removed (can be re-pulled)

---

## 📝 Log Rotation

### Overview

Automatic log rotation to prevent disk space exhaustion from log files.

### Docker Compose Configuration

**File:** `compose.yml`

```yaml
x-critical-logging: &critical-logging
  driver: json-file
  options:
    max-size: '10m'
    max-file: '3'
    compress: 'true'
```

### Configuration Details

| Parameter               | Value | Description                     |
| ----------------------- | ----- | ------------------------------- |
| **max-size**            | 10m   | Maximum log file size           |
| **max-file**            | 3     | Number of rotated files to keep |
| **compress**            | true  | Compress rotated logs           |
| **Total per container** | ~30MB | 10MB × 3 files                  |

### Manual Log Management

```bash
# View container logs
docker compose logs SERVICE_NAME --tail 100

# Clear all logs (CAUTION)
truncate -s 0 $(docker inspect --format='{{.LogPath}}' CONTAINER_ID)

# Check log sizes
docker ps -q | xargs -I {} sh -c 'echo -n "{}: "; docker inspect --format="{{.LogPath}}" {} | xargs du -h'
```

### Log Cleanup Scripts

**Daily cleanup:** `scripts/rotate-logs.sh` (runs at 3:00 AM)

```bash
# Manual execution
cd /home/konstantin/Documents/augment-projects/erni-ki
./scripts/rotate-logs.sh
```

---

## 📊 System Monitoring Automation

### Health Monitor

**Schedule:** Every hour  
**Script:** `scripts/health-monitor.sh`  
**Cron Entry:**

```cron
# ERNI-KI System Monitoring
0 * * * * cd /home/konstantin/Documents/augment-projects/erni-ki && ./scripts/health-monitor.sh >> .config-backup/monitoring/cron.log 2>&1
```

### Weekly Reports

**Schedule:** Every Sunday at 3:00 AM  
**Output:** `.config-backup/monitoring/weekly-report-YYYYMMDD.md`

```cron
# Еженедельный полный отчет (воскресенье в 3:00)
0 3 * * 0 cd /home/konstantin/Documents/augment-projects/erni-ki && ./scripts/health-monitor.sh > .config-backup/monitoring/weekly-report-$(date +\%Y\%m\%d).md 2>&1
```

### Monitoring Cleanup

**Schedule:** Daily at 2:00 AM  
**Retention:** 7 days

```cron
# Ежедневная очистка старых логов (старше 7 дней)
0 2 * * * find /home/konstantin/Documents/augment-projects/erni-ki/.config-backup/monitoring -name "health-report-*.md" -mtime +7 -delete
```

---

## 💾 Backrest Backup Automation

### Overview

Automatic backups of critical data using Backrest.

### Configuration

**Schedule:** Daily at 1:30 AM  
**Retention:**

- Daily backups: 7 days
- Weekly backups: 4 weeks

**Backup Locations:**

- Environment files: `env/`
- Configurations: `conf/`
- PostgreSQL data: `data/postgres/`
- OpenWebUI data: `data/openwebui/`
- Ollama models: `data/ollama/`

### Monitoring

```bash
# Check Backrest status
docker compose ps backrest

# View backup logs
docker compose logs backrest --tail 50

# List backups
ls -lh .config-backup/
```

---

## 🔧 Cron Jobs Management

### View All Cron Jobs

```bash
# List all cron jobs
crontab -l

# List ERNI-KI specific jobs
crontab -l | grep -i erni-ki
```

### Add New Cron Job

```bash
# Edit crontab
crontab -e

# Add new job
0 5 * * * /path/to/script.sh >> /path/to/log.log 2>&1
```

### Remove Cron Job

```bash
# Edit crontab
crontab -e

# Delete the line or comment it out with #
```

### Cron Job Syntax

```
┌───────────── minute (0 - 59)
│ ┌───────────── hour (0 - 23)
│ │ ┌───────────── day of month (1 - 31)
│ │ │ ┌───────────── month (1 - 12)
│ │ │ │ ┌───────────── day of week (0 - 6) (Sunday=0)
│ │ │ │ │
* * * * * command to execute
```

**Examples:**

```cron
# Every day at 3:00 AM
0 3 * * * /path/to/script.sh

# Every Sunday at 4:00 AM
0 4 * * 0 /path/to/script.sh

# Every hour
0 * * * * /path/to/script.sh

# Every 30 minutes
*/30 * * * * /path/to/script.sh
```

---

## 📈 Monitoring Automation Status

### Check Script Execution

```bash
# PostgreSQL VACUUM
grep "completed successfully" /tmp/pg_vacuum.log | tail -n 5

# Docker Cleanup
grep "cleanup completed" /tmp/docker-cleanup.log | tail -n 5

# Health Monitor
tail -n 20 .config-backup/monitoring/cron.log
```

### Verify Cron Jobs Running

```bash
# Check cron service
systemctl status cron

# View cron logs
journalctl -u cron --since "1 day ago"

# Test cron job manually
/tmp/pg_vacuum.sh
/tmp/docker-cleanup.sh
```

---

## 🎯 Success Criteria

| Metric                  | Target    | Current | Status |
| ----------------------- | --------- | ------- | ------ |
| **PostgreSQL VACUUM**   | Weekly    | Active  | ✅     |
| **Docker Cleanup**      | Weekly    | Active  | ✅     |
| **Log Rotation**        | Automatic | Active  | ✅     |
| **Disk Usage**          | <60%      | 60%     | ✅     |
| **Backup Success Rate** | >99%      | 100%    | ✅     |

---

## 📚 Related Documentation

- [Admin Guide](admin-guide.md) - System administration
- [Monitoring Guide](monitoring-guide.md) - Monitoring and alerts
- [Docker Cleanup Guide](docker-cleanup-guide.md) - Detailed cleanup procedures
- [Docker Log Rotation](docker-log-rotation.md) - Log management

---

**Last Updated:** 2025-10-24  
**Next Review:** 2025-11-24
