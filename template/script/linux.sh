# VARIABLES
CONF_DIR=./conf
DATA_DIR=./data
ENV_DIR=./env
TEMPLATE_DIR=./template
POSTGRES_DB=openwebui
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
DATABASE_URL=postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@db:5432/$POSTGRES_DB
PGVECTOR_DB_URL=postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@db:5432/$POSTGRES_DB
SECRET_KEY=$(openssl rand -hex 32)
DOMAIN_NAME=
TUNNEL_ID=
TUNNEL_TOKEN=
TIMEZONE=$(cat /etc/timezone)
VERBOSE=1


show_help() {
cat << EOF
Usage: ${0##*/} [-h] [-q]
  [--pg-db NAME] [--pg-user USERNAME] [--pg-password PASSWORD]
  [--tz REGION/TIMEZONE]

  --domain DOMAIN NAME
  --tunnel-id ID
  --tunnel-token TOKEN

Configure and start OWUI starter project.
  -h/--help        display this help information
  -q/--quiet       verbose mode off
  --domain         domain to use for project
  --tunnel-id      cloudflare zero-trust tunnel id
  --tunnel-token   cloudflare zero-trust tunnel token
  --pg-db          postgresql database name
  --pg-user        postgresql database user
  --pg-password    postgresql database password
  --tz             system timezone (mcp server)

EOF
}

die() {
  printf '%s\n' "$1" >&2
  exit 1
}

print_verbose() {
  if [ "$VERBOSE" -eq 1 ]; then
    echo $1
  fi
}

# PARSE ARGUMENTS
while :; do
  case $1 in
    -h|-\?|--help)
      show_help
      exit
      ;;
    -q|--quiet)
      VERBOSE=0
      ;;
    --domain)
      if [ "$2" ]; then
        DOMAIN_NAME=$2
        shift
      else
        die 'ERROR: "--domain" requires a domain.'
      fi
      ;;
    --domain=?*)
      DOMAIN_NAME=${1#*=}
      ;;
    --domain=)
      die 'ERROR: "--domain" requires a domain.'
      ;;
    --tunnel-id)
      if [ "$2" ]; then
        TUNNEL_ID=$2
        shift
      else
        die 'ERROR: "--tunnel-id" requires a tunnel id.'
      fi
      ;;
    --tunnel-id=?*)
      TUNNEL_ID=${1#*=}
      ;;
    --tunnel-id=)
      die 'ERROR: "--tunnel-id" requires a tunnel id.'
      ;;
    --tunnel-token)
      if [ "$2" ]; then
        TUNNEL_TOKEN=$2
        shift
      else
        die 'ERROR: "--tunnel-token" requires a tunnel token.'
      fi
      ;;
    --tunnel-token=?*)
      TUNNEL_TOKEN=${1#*=}
      ;;
    --tunnel-token=)
      die 'ERROR: "--tunnel-token" requires a tunnel toke.'
      ;;
    --pg-db)
      if [ "$2" ]; then
        POSTGRES_DB=$2
        shift
      else
        die 'ERROR: "--pg-db" requires a postgresql database name.'
      fi
      ;;
    --pg-db=?*)
      POSTGRES_DB=${1#*=}
      ;;
    --pg-db=)
      die 'ERROR: "--pg-db" requires a database name.'
      ;;
    --pg-user)
      if [ "$2" ]; then
        POSTGRES_USER=$2
        shift
      else
        die 'ERROR: "--pg-user" requires a postgresql user name.'
      fi
      ;;
    --pg-user=?*)
      POSTGRES_USER=${1#*=}
      ;;
    --pg-user=)
      die 'ERROR: "--pg-user" requires a user.'
      ;;
    --pg-password)
      if [ "$2" ]; then
        POSTGRES_PASSWORD=$2
        shift
      else
        die 'ERROR: "--pg-password" requires a postgresql password.'
      fi
      ;;
    --pg-password=?*)
      POSTGRES_PASSWORD=${1#*=}
      ;;
    --pg-password=)
      die 'ERROR: "--pg-password" requires a password.'
      ;;
    --tz)
      if [ "$2" ]; then
        TIMEZONE=$2
        shift
      else
        die 'ERROR: "--tz" requires a timezone.'
      fi
      ;;
    --tz=?*)
      TIMEZONE=${1#*=}
      ;;
    --tz=)
      die 'ERROR: "--tz" requires a timezone.'
      ;;
    --)
      shift
      break
      ;;
    *)
      break
  esac

  shift
done


if ! [ "$DOMAIN_NAME" ]; then
  show_help
  die 'ERROR "--domain" is required'
fi

if ! [ "$TUNNEL_ID" ]; then
  show_help
  die 'ERROR "--tunnel-id" is required'
fi

if ! [ "$TUNNEL_TOKEN" ]; then
  show_help
  die 'ERROR "--tunnel-token" is required'
fi


# GENERATE DOCKER COMPOSE
cp $TEMPLATE_DIR/compose.yml.example compose.yml
print_verbose "created compose.yml for docker"
echo

# GENERATE CONF FILES FROM TEMPLATES
mkdir -p $CONF_DIR/cloudflared
print_verbose "created base $CONF_DIR/cloudflared directory"
mkdir -p $CONF_DIR/mcposerver
print_verbose "created base $CONF_DIR/mcposerver directory"
mkdir -p $CONF_DIR/nginx/conf.d
print_verbose "created base $CONF_DIR/nginx/conf.d directory"
mkdir -p $CONF_DIR/searxng
print_verbose "created base $CONF_DIR/searxng directory"
print_verbose 

cp $TEMPLATE_DIR/conf/cloudflared/config.example $CONF_DIR/cloudflared/config.yml
print_verbose "created $CONF_DIR/cloudflared/config.yml configuration file"
cp $TEMPLATE_DIR/conf/mcposerver/config.example $CONF_DIR/mcposerver/config.json
print_verbose "created $CONF_DIR/mcposerver/config.json configuration file"
cp $TEMPLATE_DIR/conf/nginx/nginx.example $CONF_DIR/nginx/nginx.conf
print_verbose "created $CONF_DIR/nginx/nginx.conf configuration file"
cp $TEMPLATE_DIR/conf/nginx/conf.d/default.example $CONF_DIR/nginx/conf.d/default.conf
print_verbose "created $CONF_DIR/nginx/conf.d/default.conf configuration file"
cp $TEMPLATE_DIR/conf/searxng/settings.yml.example $CONF_DIR/searxng/settings.yml
print_verbose "created $CONF_DIR/searxng/settings.yml configuration file"
cp $TEMPLATE_DIR/conf/searxng/uwsgi.ini.example $CONF_DIR/searxng/uwsgi.ini
print_verbose "created $CONF_DIR/searxng/uwsgi.ini configuration file"
print_verbose

# GENERATE ENVIRONMENT FILES FROM TEMPLATES
mkdir -p $ENV_DIR
print_verbose "created base $ENV_DIR/ directory"

cp $TEMPLATE_DIR/env/auth.example $ENV_DIR/auth.env
print_verbose "created $ENV_DIR/auth.env variable file"
cp $TEMPLATE_DIR/env/cloudflared.example $ENV_DIR/cloudflared.env
print_verbose "created $ENV_DIR/cloudflared.env variable file"
cp $TEMPLATE_DIR/env/db.example $ENV_DIR/db.env
print_verbose "created $ENV_DIR/db.env variable file"
cp $TEMPLATE_DIR/env/docling.example $ENV_DIR/docling.env
print_verbose "created $ENV_DIR/docling.env variable file"
cp $TEMPLATE_DIR/env/edgetts.example $ENV_DIR/edgetts.env
print_verbose "created $ENV_DIR/edgetts.env variable file"
cp $TEMPLATE_DIR/env/mcposerver.example $ENV_DIR/mcposerver.env
print_verbose "created $ENV_DIR/mcposerver.env variable file"
cp $TEMPLATE_DIR/env/ollama.example $ENV_DIR/ollama.env
print_verbose "created $ENV_DIR/ollama.env variable file"
cp $TEMPLATE_DIR/env/openwebui.example $ENV_DIR/openwebui.env
print_verbose "created $ENV_DIR/openwebui.env variable file"
cp $TEMPLATE_DIR/env/redis.example $ENV_DIR/redis.env
print_verbose "created $ENV_DIR/redis.env variable file"
cp $TEMPLATE_DIR/env/searxng.example $ENV_DIR/searxng.env
print_verbose "created $ENV_DIR/searxng.env variable file"
cp $TEMPLATE_DIR/env/tika.example $ENV_DIR/tika.env
print_verbose "created $ENV_DIR/tika.env variable file"
cp $TEMPLATE_DIR/env/watchtower.example $ENV_DIR/watchtower.env
print_verbose "created $ENV_DIR/watchtower.env variable file"
print_verbose


## AUTH

sed -i "s|<secret-key>|$SECRET_KEY|" $ENV_DIR/auth.env
print_verbose "set secret-key in $ENV_DIR/auth.env"


## CLOUDFLARED

sed -i "s|<tunnel-id>|$TUNNEL_ID|g" $CONF_DIR/cloudflared/config.yml
print_verbose "set tunnel-id in $CONF_DIR/cloudflared/config.yml"
sed -i "s|<tunnel-token>|$TUNNEL_TOKEN|g" $ENV_DIR/cloudflared.env
print_verbose "set tunnel-token in $ENV_DIR/cloudflared.env"


## DB

sed -i "s|<db-name>|$POSTGRES_DB|g" $ENV_DIR/db.env
print_verbose "set db-name in $ENV_DIR/db.env"
sed -i "s|<db-user>|$POSTGRES_USER|g" $ENV_DIR/db.env
print_verbose "set db-user in $ENV_DIR/db.env"
sed -i "s|<db-password>|$POSTGRES_PASSWORD|g" $ENV_DIR/db.env
print_verbose "set db-password in $ENV_DIR/db.env"


## DOCLING

### nothing to do


## EDGETTS

### nothing to do


## MCPSERVER

sed -i "s|<timezone>|$TIMEZONE|" $CONF_DIR/mcposerver/config.json
print_verbose "set timezone in $CONF_DIR/mcposerver/config.json"
sed -i "s|<database-url>|$DATABASE_URL|" $CONF_DIR/mcposerver/config.json
print_verbose "set database-url in $CONF_DIR/mcposerver/config.json"


## NGINX

sed -i "s|<domain-name>|$DOMAIN_NAME|" $CONF_DIR/nginx/conf.d/default.conf
print_verbose "set domain-name in $CONF_DIR/nginx/conf.d/default.conf"


## OLLAMA

### nothing to do


## OPENWEBUI

sed -i "s|<secret-key>|$SECRET_KEY|" $ENV_DIR/openwebui.env
print_verbose "set secret-key in $ENV_DIR/openewbui.env"
sed -i "s|<domain-name>|$DOMAIN_NAME|" $ENV_DIR/openwebui.env
print_verbose "set domain-name in $ENV_DIR/openewbui.env"
sed -i "s|<database-url>|$DATABASE_URL|" $ENV_DIR/openwebui.env
print_verbose "set database-url in $ENV_DIR/openewbui.env"
sed -i "s|<pgvector-db-url>|$PGVECTOR_DB_URL|" $ENV_DIR/openwebui.env
print_verbose "set pgvector-db-url in $ENV_DIR/openewbui.env"


## REDIS

### nothing to do


## SEARXNG

sed -i "s|<secret-key>|$SECRET_KEY|" $ENV_DIR/searxng.env
print_verbose "set secret-key in $ENV_DIR/searxng.env"
sed -i "s|<domain-name>|$DOMAIN_NAME|" $ENV_DIR/searxng.env
print_verbose "set domain-name in $ENV_DIR/searxng.env"


## TIKA

### nothing to do


## WATCHTOWER

### @TODO: setup discord

print_verbose


# START DOCKER CONTAINERS

print_verbose pulling docker images and starting docker containers

docker compose up db -d
docker compose up redis -d
docker compose up ollama -d
docker compose up auth -d
docker compose up docling -d
docker compose up tika -d
docker compose up edgetts -d
docker compose up mcposerver -d
docker compose up docling -d
docker compose up redis -d
docker compose up watchtower -d
docker compose up cloudflared -d
docker compose up openwebui -d
docker compose up searxng -d
docker compose up nginx -d


# LOAD IN BROWSER

print_verbose "sleeping for 10 seconds to allow startup to complete"

sleep 10

print_verbose "opening $DOMAIN_NAME in default browser"

open https://$DOMAIN_NAME/ </dev/null &>/dev/null &

