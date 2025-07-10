#!/usr/bin/env bash

shopt -s nullglob

create_project () {
  local TEMPLATE_PATH="$1"
  local INSTALL_PATH="$2"


  pushd $TEMPLATE_PATH > /dev/null
    TEMPLATE_FILE_PATHS=()
    while IFS= read -r FULLPATH; do
      TEMPLATE_FILE_PATHS+=("${FULLPATH#${TEMPLATE_PATH}/}")
    done < <(find $TEMPLATE_PATH -name "*.template" | sort)

    print_message "\nCreating install directory $INSTALL_PATH"
    mkdir -p $1

    print_message "\nCreating template files"

    for p in "${TEMPLATE_FILE_PATHS[@]}"
    do
      TEMPLATE_FILE_NAME=$(basename $p)
      TEMPLATE_DIR_PATH=$(dirname $p)

      if [ -f $p ]; then
        print_message "--> ${p%.*}"

        mkdir -p "$INSTALL_PATH/$TEMPLATE_DIR_PATH"

        if [ $TEMPLATE_FILE_NAME == "compose.yaml.template" ]; then
          cat "$p" | \
            HOST_PORT=$HOST_PORT \
            envsubst \
            '$HOST_PORT' \
            > "$INSTALL_PATH/${p%.*}"
        else
          cat "$p" | \
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
            envsubst \
              '$DATABASE_URL,$HOST_PORT,$JWT_SECRET,$NGINX_HOST,$PGVECTOR_DB_URL,$POSTGRES_DB,$POSTGRES_HOST,$POSTGRES_USER,$POSTGRES_PASSWORD,$RAG_EMBEDDING_MODEL,$SEARXNG_SECRET,$SEARXNG_BASE_URL,$TIMEZONE,$WEBUI_SECRET_KEY,$WEBUI_URL' \
            > "$INSTALL_PATH/${p%.*}"
        fi
      else
        print_message "skipping $p"
      fi
    done
  popd > /dev/null
}

define_environment_variables () {
  if [ -z "$EMBEDDING_MODEL" ]; then
    EMBEDDING_MODEL=nomic-embed-text:latest
  fi

  if [ -z "$DECISION_MODEL" ]; then
    DECISION_MODEL=qwen3:0.6b
  fi

  print_message "\nGenerating secret key"
  if [ -z $SECRET_KEY ]; then
    SECRET_KEY=$(openssl rand -hex 32)
  else
    print_message "Using provided SECRET_KEY"
  fi

  print_message "\nCollecting database credentials"
  if [ -z "$POSTGRES_DB" ]; then
    POSTGRES_DB=owui$(openssl rand -hex 6)
  else
    print_message "Using provided POSTGRES_DB"
  fi
  if [ -z "$POSTGRES_HOST" ]; then
    POSTGRES_HOST=postgres
  else
    print_message "Using provided POSTGRES_HOST"
  fi
  if [ -z "$POSTGRES_USER" ]; then
    POSTGRES_USER=user$(openssl rand -hex 6)
  else
    print_message "Using provided POSTGRES_USER"
  fi
  if [ -z "$POSTGRES_PASSWORD" ]; then
    POSTGRES_PASSWORD=$(openssl rand -hex 12)
  else
    print_message "Using provided POSTGRES_PASSWORD"
  fi

  DATABASE_URL="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST/$POSTGRES_DB"
  PGVECTOR_DB_URL="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST/$POSTGRES_DB"

  print_message "Collecting timezone information"
  if [ -z $TIMEZONE ]; then
    TIMEZONE=$(cat /etc/timezone)
  else
    print_message "Using provided TIMEZONE"
  fi

  print_message "Collecting host credentials"
  if [ -z "$HOST_PORT" ]; then
    HOST_PORT=3000
  else
    print_message "Using provided HOST_PORT"
  fi

  print_message "Collecting nginx proxy credentials"
  if [ -z "$NGINX_HOST" ]; then
    NGINX_HOST=localhost
  else
    print_message "Using provided NGINX_HOST"
  fi
}

define_setup_variables () {
  if [ -z "$INSTALL_PATH" ]; then
    INSTALL_PATH="$HOME/MyStarters"
  else
    print_message "Using provided INSTALL_PATH"
  fi

  if [ -z "$TEMPLATE_ID" ]; then
    TEMPLATE_ID="4b35c72a-6775-41cb-a717-26276f7ae56e"
  else
    print_message "Using provided TEMPLATE_ID"
  fi

  if [ -z "$TEMPLATES_DIR" ]; then
    TEMPLATES_DIR="$HOME/.starter-templates"
  else
    print_message "Using provided TEMPLATE_DIR"
  fi

  if [ -z "$TEMPLATES_URL" ]; then
    TEMPLATES_URL="https://codeload.github.com/iamobservable/starter-templates/zip/refs/heads/main"
  else
    print_message "Using provided TEMPLATE_URL"
  fi
}

fail_if_project_directory_exists () {
  if [ -d "$1" ]; then
    print_error_and_exit "directory $1 already exists"
  fi
}

open_browser () {
  print_message "\nOpening $1 (OWUI) in the browser"
  open $1
}

print_error () {
  echo
  echo -e "\033[31m\033[22merror: \033[1m$1\033[0m"

  print_usage
}

print_error_and_exit () {
  print_error "$1"
  exit
}

print_message () {
  echo -e "\033[22m$1\033[0m"
}

print_usage () {
  command="install.sh"

  echo
  echo -e "\033[22musage: \033[32m\033[1m$command\033[0m"
  echo
  # echo -e "\033[22m\033[22m  -p, --pull                  \033[1mfetch all templates\033[0m"
  echo -e "\033[22m\033[22m  -c, --create project-name   \033[1mcreate new project\033[0m"
  echo -e "\033[22m\033[22m  -r, --remove project-name   \033[1mremove project\033[0m"
  echo -e "\033[22m\033[22m  -u, --update                \033[1mupdate starter command\033[0m"
  echo -e "\033[22m\033[22m      --ps                    \033[1mshow running container process list\033[0m"
  echo
}

pull_templates () {
  rm -rf $1
  mkdir -p $1

  local PULLTMP=`mktemp -d /tmp/open-webui-starter.XXXXXXXXXXX` || exit 1

  pushd $PULLTMP > /dev/null
    print_message "\nPulling latest templates"
    curl -s $2 > templates.zip

    local SHABASE="$(basename $2)"

    mkdir -p --mode 750 ./unzip

    unzip -q templates.zip -d ./unzip
    cp -rf ./unzip/starter-templates-$SHABASE/* $1
  popd > /dev/null

  rm -rf $PULLTMP
}

remove_project () {
  pushd $1 > /dev/null
    print_message "\nShutting down and removing containers"
    docker compose down -v

    print_message "\nRemoving environment files"
    rm -fv env/*.env

    print_message "\nRemoving mcp configuration"
    rm -fv conf/mcp/config.json

    print_message "\nRemoving compose file"
    rm -fv compose.yml
  popd > /dev/null

  rm -rfv $1
}

show_ps () {
  pushd $1 > /dev/null
    docker compose -f compose.yaml ps
  popd > /dev/null
}

start_containers () {
  pushd $1 > /dev/null

  print_message "\nStarting Ollama container"
  docker compose up ollama -d

  print_message "\nDownloading nomic-embed-text model"
  docker compose exec ollama ollama pull $EMBEDDING_MODEL

  print_message "\nDownloading $DECISION_MODEL model"
  docker compose exec ollama ollama pull $DECISION_MODEL

  print_message "\nStarting Postgres container"
  docker compose up postgres -d

  print_message "\nStarting Openwebui and dependency containers"
  docker compose up -d

  popd > /dev/null
}

update_starter () {
  local starter_script_url="https://raw.githubusercontent.com/iamobservable/open-webui-starter/refs/heads/main/starter.sh"
  curl -s $starter_script_url > $HOME/bin/starter

  print_message "starter updated:\n  see commit history for changes -> https://github.com/iamobservable/open-webui-starter/commits/main/"
}




options=$(getopt -l "create,remove,ps,pull,update,help" -o "cpruh" -- "$@")

eval set -- "$options"

if [ $1 == "--" ]; then
  print_usage
  exit
fi

while true
do
  case "$1" in
  -c|--create)
    shift
    PROJECT_NAME=$2

    if [ -z "$PROJECT_NAME" ]; then
      print_error_and_exit "missing project-name"
    fi

    define_setup_variables
    define_environment_variables

    # STARTING POINT
    fail_if_project_directory_exists "$INSTALL_PATH/$PROJECT_NAME"

    pull_templates "$TEMPLATES_DIR" "$TEMPLATES_URL"
    create_project "$TEMPLATES_DIR/$TEMPLATE_ID" "$INSTALL_PATH/$PROJECT_NAME"
    start_containers "$INSTALL_PATH/$PROJECT_NAME"

    # open_browser "http://$NGINX_HOST:$HOST_PORT/"
    ;;
  -p|--pull)
    define_setup_variables
    pull_templates "$TEMPLATES_DIR" "$TEMPLATES_URL"
    ;;
  --ps)
    shift

    PROJECT_NAME=$2

    if [ -z "$PROJECT_NAME" ]; then
      print_error_and_exit "missing project-name"
    fi

    define_setup_variables

    show_ps "$INSTALL_PATH/$PROJECT_NAME"
    ;;
  -r|--remove)
    shift
    PROJECT_NAME=$2

    if [ -z "$PROJECT_NAME" ]; then
      print_error_and_exit "missing project-name"
    fi

    define_setup_variables

    remove_project "$INSTALL_PATH/$PROJECT_NAME"
    ;;
  -u|--update)
    shift

    update_starter
    ;;
  -h|--help)
    print_usage
    shift
    break
    ;;
  *)
    break
  esac

  shift

done
