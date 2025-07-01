#!/usr/bin/env bash

# git clone https://github.com/iamobservable/open-webui-starter.git


if [ -z $EMBEDDING_MODEL ]; then
  EMBEDDING_MODEL=nomic-embed-text:latest
fi

echo
echo Generating secret key
if [ -z $SECRET_KEY ]; then
  SECRET_KEY=$(openssl rand -hex 32)
else
  echo Using provided SECRET_KEY
fi

echo
echo Collecting database credentials
if [ -z $POSTGRES_DB ]; then
  POSTGRES_DB=owui$(openssl rand -hex 6)
else
  echo Using provided POSTGRES_DB
fi
if [ -z $POSTGRES_HOST ]; then
  POSTGRES_HOST=postgres
else
  echo Using provided POSTGRES_HOST
fi
if [ -z $POSTGRES_USER ]; then
  POSTGRES_USER=user$(openssl rand -hex 6)
else
  echo Using provided POSTGRES_USER
fi
if [ -z $POSTGRES_PASSWORD ]; then
  POSTGRES_PASSWORD=$(openssl rand -hex 12)
else
  echo Using provided POSTGRES_PASSWORD
fi

DATABASE_URL="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST/$POSTGRES_DB"
PGVECTOR_DB_URL="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST/$POSTGRES_DB"

echo Collecting timezone information
if [ -z $TIMEZONE ]; then
  TIMEZONE=$(cat /etc/timezone)
else
  echo Using provided TIMEZONE
fi

echo Collecting host credentials
if [ -z $HOST_PORT ]; then
  HOST_PORT=4000
else
  echo Using provided HOST_PORT
fi

echo Collecting nginx proxy credentials
if [ -z $NGINX_HOST ]; then
  NGINX_HOST=localhost
else
  echo Using provided NGINX_HOST
fi


echo
echo Inserting environment variables

declare -a paths=("compose.yml" "env/auth.env" "env/docling.env" "env/edgetts.env" "env/mcp.env" "env/nginx.env" "env/ollama.env" "env/openwebui.env" "env/postgres.env" "env/redis.env" "env/searxng.env" "env/tika.env" "env/watchtower.env" "conf/mcp/config.json")

for p in "${paths[@]}"
do
  if [ ! -f $p ]; then
    echo "--> $p"
    if [ $p == "compose.yml" ]; then
      cat "${p%.*}.example" | \
        HOST_PORT=$HOST_PORT \
        envsubst > $p
    else
      cat "${p%.*}.example" | \
        DATABASE_URL=$DATABASE_URL \
        HOST_PORT=$HOST_PORT \
        JWT_SECRET=$SECRET_KEY \
        NGINX_HOST=$NGINX_HOST \
        PGVECTOR_DB_URL=$PGVECTOR_DB_URL \
        POSTGRES_DB=$POSTGRES_DB \
        POSTGRES_HOST=$POSTGRES_HOST \
        POSTGRES_USER=$POSTGRES_USER \
        POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
        RAG_EMBEDDING_MODEL=$EMBEDDING_MODEL \
        SEARXNG_SECRET=$SECRET_KEY \
        SEARXNG_BASE_URL="https://$NGINX_HOST:$HOST_PORT/searxng" \
        TIMEZONE=$TIMEZONE \
        WEBUI_SECRET_KEY=$SECRET_KEY \
        WEBUI_URL="https://$NGINX_HOST:$HOST_PORT" \
        envsubst > $p
    fi
  else
    echo "skipping $p"
  fi
done

echo
echo Starting Ollama container
docker compose up ollama -d

echo
echo Downloading nomic-embed-text model
docker compose exec ollama ollama pull $EMBEDDING_MODEL

echo
echo Downloading qwen3:0.6b model
docker compose exec ollama ollama pull qwen3:0.6b

echo
echo Starting Postgres container
docker compose up postgres -d

echo
echo Starting Openwebui and dependency containers
docker compose up -d


sleep 10

echo
echo Opening OWUI in a browser windows
open http://$NGINX_HOST:$HOST_PORT/

