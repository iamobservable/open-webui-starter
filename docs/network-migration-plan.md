# ERNI-KI Network Architecture Migration Plan

## 📊 Current State Analysis

### Current Network Configuration
- **Active Network:** `erni-ki-network` (172.18.0.0/16)
- **Containers:** 23 containers in single network
- **Performance:** Good (inter-container latency <2ms)
- **Issues:** No network segmentation, all services in same broadcast domain

### Planned Network Architecture
```
Frontend Network (172.20.0.0/16) - Public-facing services
├── nginx (172.20.0.100) - Reverse proxy
├── openwebui (172.20.0.20) - Web interface
└── cloudflared (172.20.0.10) - Tunnel service

Backend Network (172.21.0.0/16) - Application services
├── ollama (172.21.0.90) - AI inference
├── litellm (172.21.0.30) - AI gateway
├── searxng (172.21.0.60) - Search engine
├── auth (172.21.0.70) - Authentication
└── docling (172.21.0.80) - Document processing

Internal Network (172.23.0.0/16) - Data services
├── postgres (172.23.0.40) - Database
├── redis (172.23.0.50) - Cache
└── High-performance inter-service communication
```

## 🎯 Migration Strategy

### Phase 1: Preparation (Estimated: 30 minutes)
**Objective:** Prepare for migration without service disruption

**Steps:**
1. **Backup Current Configuration** (5 min)
   ```bash
   mkdir -p .config-backup/network-migration-$(date +%Y%m%d-%H%M%S)
   docker network inspect erni-ki-network > .config-backup/network-migration-*/current-network.json
   docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Networks}}" > .config-backup/network-migration-*/current-containers.txt
   ```

2. **Validate Planned Networks Exist** (5 min)
   ```bash
   docker network ls | grep -E "(frontend|backend|internal)"
   docker network inspect erni-ki-frontend erni-ki-backend erni-ki-internal
   ```

3. **Create Migration Scripts** (15 min)
   - Container stop/start sequences
   - Network attachment scripts
   - Rollback procedures

4. **Test Network Connectivity** (5 min)
   - Verify current performance baseline
   - Document current IP assignments

### Phase 2: Data Services Migration (Estimated: 45 minutes)
**Objective:** Migrate database and cache services to internal network

**Critical Services:** postgres, redis
**Downtime:** ~5 minutes per service

**Steps:**
1. **Migrate PostgreSQL** (20 min)
   ```bash
   # Stop dependent services
   docker-compose stop openwebui
   
   # Connect postgres to internal network
   docker network connect erni-ki-internal erni-ki-db-1
   docker network disconnect erni-ki-network erni-ki-db-1
   
   # Update connection strings in dependent services
   # Test connectivity from internal network
   
   # Restart dependent services
   docker-compose start openwebui
   ```

2. **Migrate Redis** (15 min)
   ```bash
   # Similar process for Redis
   docker network connect erni-ki-internal erni-ki-redis-1
   docker network disconnect erni-ki-network erni-ki-redis-1
   ```

3. **Validation** (10 min)
   - Test database connectivity
   - Verify cache functionality
   - Check application health

### Phase 3: Backend Services Migration (Estimated: 60 minutes)
**Objective:** Move application services to backend network

**Services:** ollama, litellm, searxng, auth, docling
**Downtime:** ~2 minutes per service

**Steps:**
1. **Migrate AI Services** (25 min)
   - ollama (GPU service - critical)
   - litellm (API gateway)
   
2. **Migrate Search and Auth** (20 min)
   - searxng (search engine)
   - auth (authentication service)
   
3. **Migrate Document Processing** (15 min)
   - docling (document conversion)

### Phase 4: Frontend Services Migration (Estimated: 30 minutes)
**Objective:** Move public-facing services to frontend network

**Services:** nginx, openwebui, cloudflared
**Downtime:** ~10 minutes total

**Steps:**
1. **Migrate OpenWebUI** (10 min)
2. **Migrate Nginx** (15 min) - Most critical
3. **Migrate Cloudflared** (5 min)

### Phase 5: Cleanup and Optimization (Estimated: 15 minutes)
**Objective:** Remove old network and optimize configuration

**Steps:**
1. **Remove old network connections**
2. **Update nginx upstream configurations**
3. **Optimize DNS resolution settings**
4. **Final validation**

## ⚠️ Risk Assessment

### High Risk Items
1. **Nginx Migration** - Single point of failure
   - **Mitigation:** Prepare rollback script, test configuration
   - **Downtime:** 5-10 minutes
   
2. **PostgreSQL Migration** - Data service
   - **Mitigation:** Database backup before migration
   - **Downtime:** 3-5 minutes
   
3. **Ollama GPU Service** - AI inference
   - **Mitigation:** Verify GPU access in new network
   - **Downtime:** 2-3 minutes

### Medium Risk Items
1. **DNS Resolution Changes** - Service discovery
   - **Mitigation:** Update resolver settings, test connectivity
   
2. **Inter-service Communication** - API calls
   - **Mitigation:** Gradual migration, connectivity tests

### Low Risk Items
1. **Monitoring Services** - Non-critical
2. **Utility Services** - Can be migrated last

## 🔄 Rollback Plan

### Immediate Rollback (if issues detected)
```bash
# Stop all services
docker-compose down

# Restore original network configuration
docker network disconnect erni-ki-frontend erni-ki-nginx-1
docker network disconnect erni-ki-backend erni-ki-openwebui-1
docker network connect erni-ki-network erni-ki-nginx-1
docker network connect erni-ki-network erni-ki-openwebui-1

# Restart services
docker-compose up -d
```

### Full System Rollback
```bash
# Complete rollback to original state
./scripts/network-rollback.sh
```

## 📈 Expected Benefits

### Performance Improvements
- **Reduced broadcast traffic** - Network segmentation
- **Optimized routing** - Direct internal communication
- **Better resource isolation** - Service-specific networks

### Security Enhancements
- **Network segmentation** - Reduced attack surface
- **Service isolation** - Limited inter-service access
- **Improved monitoring** - Network-level visibility

### Operational Benefits
- **Clearer architecture** - Logical service grouping
- **Easier troubleshooting** - Network-based diagnostics
- **Better scalability** - Service-specific scaling

## 🎯 Success Criteria

### Functional Requirements
- ✅ All 25+ services remain healthy
- ✅ HTTPS endpoints respond <2s
- ✅ RAG functionality works correctly
- ✅ No data loss or corruption

### Performance Requirements
- ✅ Inter-service latency <5ms
- ✅ DNS resolution <100ms
- ✅ Overall system performance maintained

### Operational Requirements
- ✅ Total migration time <3 hours
- ✅ Individual service downtime <10 minutes
- ✅ Successful rollback capability

## 📋 Migration Checklist

### Pre-Migration
- [ ] Create configuration backup
- [ ] Validate planned networks exist
- [ ] Prepare migration scripts
- [ ] Test rollback procedures
- [ ] Schedule maintenance window

### During Migration
- [ ] Execute Phase 1: Preparation
- [ ] Execute Phase 2: Data Services
- [ ] Execute Phase 3: Backend Services
- [ ] Execute Phase 4: Frontend Services
- [ ] Execute Phase 5: Cleanup

### Post-Migration
- [ ] Validate all services healthy
- [ ] Test HTTPS endpoints
- [ ] Verify RAG functionality
- [ ] Monitor performance metrics
- [ ] Document lessons learned

## 🚀 Recommendation

**Current Assessment:** Migration is **OPTIONAL** at this time.

**Rationale:**
- Current network performs well (all tests passing)
- System is stable and functional
- Migration introduces risk without immediate benefit
- Focus should be on RAG optimization and feature development

**Alternative Approach:**
- Implement planned architecture for **new deployments**
- Migrate during **major system upgrades**
- Use current architecture as **production baseline**
