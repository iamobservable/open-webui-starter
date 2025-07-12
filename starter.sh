#!/usr/bin/env bash

TEMPLATES_DIR="$HOME/.starter-templates"
TEMPLATE_ID="4b35c72a-6775-41cb-a717-26276f7ae56e"

shopt -s nullglob

define_environment_variables () {
  if [ -z "$EMBEDDING_MODEL" ]; then
    EMBEDDING_MODEL=nomic-embed-text:latest
  fi

  if [ -z "$DECISION_MODEL" ]; then
    DECISION_MODEL=qwen3:0.6b
  fi

  print_message "\ngenerating secret key"
  if [ -z $SECRET_KEY ]; then
    SECRET_KEY=$(openssl rand -hex 32)
  else
    print_message "Using provided SECRET_KEY"
  fi

  print_message "\ncollecting database credentials"
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

  print_message "collecting timezone information"
  if [ -z $TIMEZONE ]; then
    TIMEZONE=$(cat /etc/timezone)
  else
    print_message "Using provided TIMEZONE"
  fi

  print_message "collecting host credentials"
  if [ -z "$HOST_PORT" ]; then
    HOST_PORT=3000
  else
    print_message "Using provided HOST_PORT"
  fi

  print_message "collecting nginx proxy credentials"
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

  if [ -z "$TEMPLATES_URL" ]; then
    TEMPLATES_URL="https://codeload.github.com/iamobservable/starter-templates/zip/refs/heads/main"
  else
    print_message "Using provided TEMPLATE_URL"
  fi
}

fail_if_no_project () {
  if [ -z "$1" ]; then
    print_error_and_exit "missing project-name"
  fi
}

fail_if_project_directory_does_not_exist () {
  if ! [ -d "$1" ]; then
    print_error_and_exit "project directory $1 does not exist"
  fi
}

fail_if_project_directory_exists () {
  if [ -d "$1" ]; then
    print_error_and_exit "project directory $1 already exists"
  fi
}

open_browser () {
  print_message "\nopening $1 (OWUI) in the browser"
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
  command="$(basename $0)"

  echo
  echo -e "\033[22musage: \033[32m\033[1m$command\033[0m"
  echo
  echo -e "\033[22m\033[22mproject commands:\033[0m"
  echo -e "\033[22m\033[22m      --containers    project-name                     \033[1mshow running containers\033[0m"
  echo -e "\033[22m\033[22m  -c, --create        project-name  [--template uuid]  \033[1mcreate new project\033[0m"
  echo -e "\033[22m\033[22m  -p, --projects                                       \033[1mlist starter projects\033[0m"
  echo -e "\033[22m\033[22m  -r, --remove        project-name                     \033[1mremove project\033[0m"
  echo -e "\033[22m\033[22m      --start         project-name                     \033[1mstart project\033[0m"
  echo -e "\033[22m\033[22m      --stop          project-name                     \033[1mstop project\033[0m"
  echo
  echo -e "\033[22m\033[22mtemplate commands:\033[0m"
  echo -e "\033[22m\033[22m      --copytemplate  template-id                      \033[1mmake copy of template\033[0m"
  echo -e "\033[22m\033[22m      --pull                                           \033[1mpull latest templates\033[0m"
  echo -e "\033[22m\033[22m      --templates                                      \033[1mlist starter templates\033[0m"
  echo
  echo -e "\033[22m\033[22msystem commands:\033[0m"
  echo -e "\033[22m\033[22m  -u, --update                                         \033[1mupdate starter command\033[0m"
  echo
}

project_boot () {
  pushd "$1/$2" > /dev/null
    print_message "\nstarting Ollama container"
    docker compose up ollama -d

    print_message "\ndownloading nomic-embed-text model"
    docker compose exec ollama ollama pull $EMBEDDING_MODEL

    print_message "\ndownloading $DECISION_MODEL model"
    docker compose exec ollama ollama pull $DECISION_MODEL

    print_message "\nstarting Postgres container"
    docker compose up postgres -d

    print_message "\nstarting Openwebui and dependency containers"
    docker compose up -d
  popd > /dev/null
}

project_containers () {
  fail_if_no_project $2
  fail_if_project_directory_does_not_exist "$1/$2"

  pushd $1/$2 > /dev/null
    docker compose -f compose.yaml ps
  popd > /dev/null
}

project_create () {
  local TEMPLATE_PATH="$1"
  local INSTALL_PATH="$2/$3"

  pushd $TEMPLATE_PATH > /dev/null
    local PATHS=()

    while IFS= read -r FULLPATH; do
      PATHS+=("${FULLPATH#${TEMPLATE_PATH}/}")
    done < <(find $TEMPLATE_PATH -name "*.template" | sort)

    print_message "\ncreating new project from template $TEMPLATE_ID"
    print_message "--> install directory $INSTALL_PATH"

    mkdir -p $1

    print_message "\ncreating template files"

    for p in "${PATHS[@]}"
    do
      local PATHS_FILE_NAME=$(basename $p)
      local PATHS_TEMPLATE_PATH=$(dirname $p)

      if [ -f $p ]; then
        print_message "--> ${p%.*}"

        mkdir -p "$INSTALL_PATH/$PATHS_TEMPLATE_PATH"

        if [ $PATHS_FILE_NAME == "compose.yaml.template" ]; then
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

project_remove () {
  fail_if_no_project "$2"
  fail_if_project_directory_does_not_exist "$1/$2"

  pushd "$1/$2" > /dev/null
    print_message "\nshutting down and removing containers"
    docker compose down -v
  popd > /dev/null

  print_message "\nremoving files and directory"
  rm -rfv "$1/$2"
}

project_start () {
  fail_if_no_project "$2"
  fail_if_project_directory_does_not_exist "$1/$2"

  pushd "$1/$2" > /dev/null
    docker compose -f compose.yaml up -d
  popd > /dev/null
}

project_stop () {
  fail_if_no_project "$2"
  fail_if_project_directory_does_not_exist "$1/$2"

  pushd "$1/$2" > /dev/null
    docker compose -f compose.yaml down
  popd > /dev/null
}

projects_list () {
  local INSTALL_DIR="$1"

  pushd $INSTALL_DIR > /dev/null
    while IFS= read -r FULLPATH; do
      local PROJECT_NAME="$(basename ${FULLPATH#${INSTALL_DIR}/})"
      
      print_message "\n\033[1m$FULLPATH\033[0m"
      # print_message "   \033[1m$PROJECT_NAME -> \033[3m$FULLPATH"

      if [ -f "$FULLPATH/locker.yaml" ]; then
        print_message "\e[1;35;3m$(head -n4 "$FULLPATH/locker.yaml" | tail -n +2)\033[0m"
      fi
    done < <(find $INSTALL_DIR -maxdepth 1 -mindepth 1 -type d | sort)
  popd > /dev/null
}

set_action_or_fail () {
  if [ -z "$ACTION" ]; then
    ACTION="$1"
  else
    print_error_and_exit "command \"$ACTION\" already set. cannot set again to \"$1\""
  fi
}

template_copy () {
  print_message "copying template $2"

  COPY_ID=$(uuidgen)

  cp -rf "$1/$2" "$1/$COPY_ID"

  print_message "created copy $COPY_ID"
}

templates_list () {
  pushd $1 > /dev/null
    while IFS= read -r FULLPATH; do
      local UUID="$(basename ${FULLPATH#${INSTALL_DIR}/})"
      
      print_message "\n\033[1m$FULLPATH\033[0m"
      print_message "\e[1;35;3m$(head -n4 "$UUID/locker.yaml" | tail -n +2)\033[0m"
    done < <(find $1 -maxdepth 1 -mindepth 1 -type d | sort)
  popd > /dev/null
}

templates_pull () {
  if [ "$OPT_NOPULL" == "true" ]; then
    print_message "\nskipping template fetching"
    return
  fi

  mkdir -p $1

  local PULLTMP=`mktemp -d /tmp/open-webui-starter.XXXXXXXXXXX` || exit 1

  pushd $PULLTMP > /dev/null
    print_message "\npulling latest templates"
    curl -fsSL $2 > templates.zip

    local SHABASE="$(basename $2)"

    mkdir -p --mode 750 ./unzip
    unzip -q templates.zip -d ./unzip

    while IFS= read -r FULLPATH; do
      ITEM_NAME=$(basename $FULLPATH)

      if !(diff $HOME/.starter-templates/$ITEM_NAME $FULLPATH > /dev/null 2>&1); then
        echo "updating template $ITEM_NAME"
        rm -rfv $HOME/.starter-templates/$ITEM_NAME
        cp -rf $FULLPATH $HOME/.starter-templates/$ITEM_NAME
      fi
    done < <(find ./unzip/starter-templates-$SHABASE/* -maxdepth 0 -mindepth 0 | sort)
  popd > /dev/null

  rm -rf $PULLTMP
}

update_starter () {
  local starter_script_url="https://raw.githubusercontent.com/iamobservable/open-webui-starter/refs/heads/main/starter.sh"
  curl -s $starter_script_url > $HOME/bin/starter

  print_message "\nstarter updated:\n  see commit history for changes -> https://github.com/iamobservable/open-webui-starter/commits/main/"
}



set -e

options=$(getopt -l "containers,copytemplate,create,remove,nopull,projects,pull,stop,start,template,templates,update,help" -o "cpruh" -- "$@")
eval set -- "$options"

define_setup_variables 

while [ $# -gt 0 ]; do
  case $1 in
  --containers)
    set_action_or_fail "containers"
    ;;
  --copytemplate)
    set_action_or_fail "copytemplate"
    ;;
  -c|--create)
    set_action_or_fail "create"
    ;;
  -p|--projects)
    set_action_or_fail "projects"
    ;;
  --pull)
    set_action_or_fail "pull"
    ;;
  -r|--remove)
    set_action_or_fail "remove"
    ;;
  --start)
    set_action_or_fail "start"
    ;;
  --stop)
    set_action_or_fail "stop"
    ;;
  --template)
    shift

    if [ "$1" == "--" ] && [ -d "$TEMPLATES_DIR/$3" ]; then
      TEMPLATE_ID=$3
    fi

    ;;
  --templates)
    set_action_or_fail "templates"
    ;;
  -u|--update)
    set_action_or_fail "update"
    ;;
  -h|--help)
    set_action_or_fail "help"
    ;;
  *)
    if ! [[ $1 == "--" ]]; then
      break
    fi
    ;;
  esac

  shift
done


case $ACTION in
containers)
  PROJECT_NAME="$1"
  project_containers "$INSTALL_PATH" "$PROJECT_NAME"
  ;;
copytemplate)
  TEMPLATE_ID="$1"
  template_copy "$TEMPLATES_DIR" "$TEMPLATE_ID"
  ;;
create)
  PROJECT_NAME="$1"
  fail_if_no_project $PROJECT_NAME
  fail_if_project_directory_exists "$INSTALL_PATH/$PROJECT_NAME"

  templates_pull "$TEMPLATES_DIR" "$TEMPLATES_URL"

  define_environment_variables
  project_create "$TEMPLATES_DIR/$TEMPLATE_ID" "$INSTALL_PATH" "$PROJECT_NAME"
  project_boot "$INSTALL_PATH" "$PROJECT_NAME"
  ;;
projects)
  projects_list "$INSTALL_PATH"
  ;;
pull)
  templates_pull "$TEMPLATES_DIR" "$TEMPLATES_URL"
  ;;
remove)
  PROJECT_NAME="$1"
  project_remove "$INSTALL_PATH" "$PROJECT_NAME"
  ;;
start)
  PROJECT_NAME="$1"
  project_start "$INSTALL_PATH" "$1"
  ;;
stop)
  PROJECT_NAME="$1"
  project_stop "$INSTALL_PATH" "$1"
  ;;
templates)
  templates_list "$TEMPLATES_DIR"
  ;;
update)
  update_starter
  ;;
*)
  print_usage
  ;;
esac
