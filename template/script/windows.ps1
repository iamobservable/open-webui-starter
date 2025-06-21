# @TODO: LOTS OF WORK AHEAD TO ADD POWERSHELL SCRIPT


# VARIABLES
CONF_DIR=./conf
ENV_DIR=./env
TEMPLATE_DIR=./template
# DOMAIN_NAME=$1
DOMAIN_NAME=uncommon.vision
SECRET_KEY=$(openssl rand -hex 32)
TUNNEL_ID=test-tunnel-id
TUNNEL_TOKEN=test-tunnel-token
TIMEZONE=$(cat /etc/timezone) #linux
# TIMEZONE=$(readlink /etc/localtime | sed 's#/var/db/timezone/zoneinfo/##g) #macos
POSTGRES_DB=openwebui
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
DATABASE_URL=postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@db:5432/$POSTGRES_DB
PGVECTOR_DB_URL=postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@db:5432/$POSTGRES_DB


# GENERATE DOCKER COMPOSE
cp compose.yml.example compose.yml

# GENERATE CONF FILES FROM TEMPLATES
cp $TEMPLATE_DIR/conf/cloudflared/config.example $CONF_DIR/cloudflared/config.yml
cp $TEMPLATE_DIR/conf/mcposerver/config.example $CONF_DIR/mcposerver/config.json
cp $TEMPLATE_DIR/conf/nginx/nginx.example $CONF_DIR/nginx/nginx.conf
cp $TEMPLATE_DIR/conf/nginx/conf.d/default.example $CONF_DIR/nginx/conf.d/default.conf
cp $TEMPLATE_DIR/conf/searxng/settings.yml.example $CONF_DIR/searxng/settings.yml
cp $TEMPLATE_DIR/conf/searxng/uwsgi.ini.example $CONF_DIR/searxng/uwsgi.ini

# GENERATE ENVIRONMENT FILES FROM TEMPLATES
cp $TEMPLATE_DIR/env/auth.example $ENV_DIR/auth.env
cp $TEMPLATE_DIR/env/cloudflared.example $ENV_DIR/cloudflared.env
cp $TEMPLATE_DIR/env/db.example $ENV_DIR/db.env
cp $TEMPLATE_DIR/env/docling.example $ENV_DIR/docling.env
cp $TEMPLATE_DIR/env/edgetts.example $ENV_DIR/edgetts.env
cp $TEMPLATE_DIR/env/mcposerver.example $ENV_DIR/mcposerver.env
cp $TEMPLATE_DIR/env/ollama.example $ENV_DIR/ollama.env
cp $TEMPLATE_DIR/env/openwebui.example $ENV_DIR/openwebui.env
cp $TEMPLATE_DIR/env/redis.example $ENV_DIR/redis.env
cp $TEMPLATE_DIR/env/searxng.example $ENV_DIR/searxng.env
cp $TEMPLATE_DIR/env/tika.example $ENV_DIR/tika.env
cp $TEMPLATE_DIR/env/watchtower.example $ENV_DIR/watchtower.env


## AUTH

sed -i "s|<secret-key>|$SECRET_KEY|" $ENV_DIR/auth.env # linux
# sed -i '' "s|<secret-key>|$SECRET_KEY|" $ENV_DIR/auth.env # macos
# @TODO: POWERSHELL https://github.com/searxng/searxng-docker#how-to-use-it


## CLOUDFLARED

sed -i "s|<tunnel-id>|$TUNNEL_ID|g" $CONF_DIR/cloudflared/config.yml # linux
# sed -i '' "s|<tunnel-id>|$TUNNEL_ID|" $CONF_DIR/cloudflared/config.yml # macos
# @TODO: POWERSHELL https://github.com/searxng/searxng-docker#how-to-use-it

sed -i "s|<tunnel-token>|$TUNNEL_TOKEN|g" $ENV_DIR/cloudflared.env # linux
# sed -i '' "s|<tunnel-token>|$TUNNEL_TOKEN|g" $ENV_DIR/cloudflared.env # macos
# @TODO: POWERSHELL https://github.com/searxng/searxng-docker#how-to-use-it


## DB

sed -i "s|<db-name>|$POSTGRES_DB|g" $ENV_DIR/db.env # linux
# sed -i '' "s|<db-name>|$POSTGRES_DB|g" $ENV_DIR/db.env # macos
# @TODO: POWERSHELL https://github.com/searxng/searxng-docker#how-to-use-it

sed -i "s|<db-user>|$POSTGRES_USER|g" $ENV_DIR/db.env # linux
# sed -i '' "s|<db-user>|$POSTGRES_USER|g" $ENV_DIR/db.env # macos
# @TODO: POWERSHELL https://github.com/searxng/searxng-docker#how-to-use-it

sed -i "s|<db-password>|$POSTGRES_PASSWORD|g" $ENV_DIR/db.env # linux
# sed -i '' "s|<db-password>|$POSTGRES_PASSWORD|g" $ENV_DIR/db.env # macos
# @TODO: POWERSHELL https://github.com/searxng/searxng-docker#how-to-use-it


## DOCLING

### nothing to do


## EDGETTS

### nothing to do


## MCPSERVER

sed -i "s|<timezone>|$TIMEZONE|" $CONF_DIR/mcposerver/config.json # linux
# sed -i '' "s|<timezone>|$TIMEZONE|" $CONF_DIR/mcposerver/config.json # macos
# @TODO: POWERSHELL https://github.com/searxng/searxng-docker#how-to-use-it

sed -i "s|<database-url>|$DATABASE_URL|" $CONF_DIR/mcposerver/config.json # linux
# sed -i '' "s|<database-url>|$DATABASE_URL|" $CONF_DIR/mcposerver/config.json # macos
# @TODO: POWERSHELL https://github.com/searxng/searxng-docker#how-to-use-it


## NGINX

sed -i "s|<domain-name>|$DOMAIN_NAME|" $CONF_DIR/nginx/conf.d/default.conf # linux
# sed -i '' "s|<domain-name>|$DOMAIN_NAME|" $CONF_DIR/nginx/conf.d/default.conf # macos
# @TODO: POWERSHELL https://github.com/searxng/searxng-docker#how-to-use-it


## OLLAMA

### nothing to do


## OPENWEBUI

sed -i "s|<secret-key>|$SECRET_KEY|" $ENV_DIR/openwebui.env # linux
# sed -i '' "s|<secret-key>|$SECRET_KEY|" $ENV_DIR/openwebui.env # macos
# @TODO: POWERSHELL https://github.com/searxng/searxng-docker#how-to-use-it

sed -i "s|<domain-name>|$DOMAIN_NAME|" $ENV_DIR/openwebui.env # linux
# sed -i '' "s|<domain-name>|$DOMAIN_NAME|" $ENV_DIR/openwebui.env # macos
# @TODO: POWERSHELL https://github.com/searxng/searxng-docker#how-to-use-it

sed -i "s|<database-url>|$DATABASE_URL|" $ENV_DIR/openwebui.env # linux
# sed -i '' "s|<database-url>|$DATABASE_URL|" $ENV_DIR/openwebui.env # macos
# @TODO: POWERSHELL https://github.com/searxng/searxng-docker#how-to-use-it

sed -i "s|<pgvector-db-url>|$PGVECTOR_DB_URL|" $ENV_DIR/openwebui.env # linux
# sed -i '' "s|<pgvector-db-url>|$PGVECTOR_DB_URL|" $ENV_DIR/openwebui.env # macos
# @TODO: POWERSHELL https://github.com/searxng/searxng-docker#how-to-use-it


## REDIS

### nothing to do


## SEARXNG

sed -i "s|<secret-key>|$SECRET_KEY|" $ENV_DIR/searxng.env # linux
# sed -i '' "s|<secret-key>|$SECRET_KEY|" $ENV_DIR/searxng.env # macos
# @TODO: POWERSHELL https://github.com/searxng/searxng-docker#how-to-use-it

sed -i "s|<domain-name>|$DOMAIN_NAME|" $ENV_DIR/searxng.env # linux
# sed -i '' "s|<domain-name>|$DOMAIN_NAME|" $ENV_DIR/searxng.env # macos
# @TODO: POWERSHELL https://github.com/searxng/searxng-docker#how-to-use-it


## TIKA

### nothing to do


## WATCHTOWER

### @TODO: setup discord



# START OLLAMA CONTAINER AND ADD LLM

docker pull ollama
docker compose up ollama -d
docker compose exec ollama "ollama pull llama3.2:3b"


# START ADDITIONAL CONTAINERS

docker compose up -d


# LOAD IN BROWSER

open https://$DOMAIN_NAME/



