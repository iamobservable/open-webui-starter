#!/usr/bin/env bash

VERBOSE=1
TEMPLATES_DIR="$HOME/.starter-templates"
TEMPLATE_ID="4b35c72a-6775-41cb-a717-26276f7ae56e"

declare -gA USER_INPUTS

shopt -s nullglob

collect_user_inputs () {
  local locker_file="$1"
  
  print_message "\nConfiguration inputs [\e[1;35menter for default value\e[0m]\n"
  
  # Get all input keys from YAML
  local keys=($(yq eval '.inputs[].key' "$locker_file"))
  
  # Process each input
  for key in "${keys[@]}"; do
    local title=$(yq eval ".inputs[] | select(.key == \"$key\") | .title" "$locker_file")
    local default=$(yq eval ".inputs[] | select(.key == \"$key\") | .default" "$locker_file")
    local input_type=$(yq eval ".inputs[] | select(.key == \"$key\") | .type" "$locker_file")

    # Handle dynamic inputs
    if [[ $input_type == "dynamic:RandStr "* ]]; then
      # Extract length from "dynamic:RandStr 16"
      local length=${input_type##*RandStr }
      local random_value=$(openssl rand -hex $((length/2)) | cut -c1-$length)
      USER_INPUTS[${key^^}]="$random_value"
      print_verbose_message "--> dynamic:RandStr ${key^^} $random_value"
      
    # Handle Timezone lookup
    elif [[ $input_type == "dynamic:Timezone" ]]; then
      system_timezone=$(timedatectl status | grep "zone" | sed -e 's/^[ ]*Time zone: \(.*\) (.*)$/\1/g')
      USER_INPUTS[${key^^}]="$system_timezone"
      print_verbose_message "--> dynamic:Timezone ${key^^} $system_timezone"

    # Handle static string
    elif [[ $input_type == "static:Str "* ]]; then
      # Extract static string from "static:String a static string"
      local static_string=${input_type##*Str }
      print_verbose_message "----> $static_string"
      USER_INPUTS[${key^^}]="$static_string"
      print_verbose_message "--> static:Str ${key^^} $static_string"

    # Handle regular inputs with user prompts
    elif [[ $input_type == "null" || -z $input_type ]]; then
      echo -e -n "$title [\e[1;35m$default\e[0m]? "
      read user_input
      USER_INPUTS[${key^^}]="${user_input:-$default}"
      print_verbose_message "--> human:input ${key^^} ${user_input:-$default}"
    fi
  done
}

define_setup_variables () {
  if [ -z "$INSTALL_PATH" ]; then
    INSTALL_PATH="$HOME/MyStarters"
  else
    print_verbose_message "Using provided INSTALL_PATH"
  fi

  if [ -z "$TEMPLATES_URL" ]; then
    TEMPLATES_URL="https://codeload.github.com/iamobservable/starter-templates/zip/refs/heads/main"
  else
    print_verbose_message "Using provided TEMPLATE_URL"
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

generate_from_template () {
  local template_dir="$1"
  local template_id="$2"
  local install_path="$3"
  local project_name="$4"
  local template_path="$template_dir/$template_id"
  local locker_file="$template_path/locker.yaml.template"

  # create array for template file paths
  local template_files=()

  # find list of files ending in .template
  # trim template path prefix from the files found
  while IFS= read -r FULL_PATH; do
    template_files+=("${FULL_PATH#${template_path}/}")
  done < <(find "$template_path" -name "*.template" | sort)

  # create a directory in the install_path with the name of the project_name variable
  print_message "\ncreating new project from template $template_id"
  print_verbose_message "--> install directory $install_path/$project_name"
  mkdir -p "$install_path/$project_name"

  # iterate the template file paths array
  print_message "\ncreating template files"
  for template_file in "${template_files[@]}"; do
    # parse the iteration file path value creating a variable for both the file name and basename directory
    local file_name=$(basename "$template_file")
    local file_directory=$(dirname "$template_file")
    
    # create a directory based on the basename directory, keep in mind the directory may be multiple levels of directories
    mkdir -p "$install_path/$project_name/$file_directory"
    
    # copy the file from the template_path directory into the newly created project directory, remove .template from the end of the file path
    local source_file="$template_path/$template_file"
    local dest_file="$install_path/$project_name/${template_file%.*}"

    print_verbose_message "--> template file $dest_file"
    cp "$source_file" "$dest_file"
  done

  # fetch all assignments from locker.yaml inside the install_path
  local assignment_count=$(yq eval '.assignments | length' "$locker_file")

  # iterate all assignments from step #10
  print_message "\napplying assignments"
  for ((i=0; i<assignment_count; i++)); do
    # create a local variables path, name, format, inputs
    local path=$(yq eval ".assignments[$i].path" "$locker_file")
    local service=$(yq eval ".assignments[$i].service" "$locker_file")
    local file_path="$install_path/$project_name/$path"
    local name=$(yq eval ".assignments[$i].name" "$locker_file")
    local uppercase_name="${name^^}"
    local format=$(yq eval ".assignments[$i].format" "$locker_file")
    local inputs=($(yq eval ".assignments[$i].inputs[]?" "$locker_file"))

    print_verbose_message "--> updating $path"

    # create a local variable value that uses printf with the format and inputs to generate a dynamic value
    local format_args=()
    for input_key in "${inputs[@]}"; do
      local uppercase_key="${input_key^^}"
      format_args+=("${USER_INPUTS[$uppercase_key]}")
    done

    local value
    if [[ ${#format_args[@]} -gt 0 ]]; then
      value=$(printf "$format" "${format_args[@]}")
    else
      value="$format"  # No substitution needed
    fi

    # check if path does not exist in the install path
    # if the path does not exist, create a new file based on the path name
    if [[ $path != "null" ]]; then
      mkdir -p "$(dirname "$file_path")"

      if [[ ! -f "$file_path" ]]; then
        touch "$file_path"
      fi

      # append a new value to the newly created file. the line should be in the format $name="$value"
      # check if any lines in the file $file_path start with the value $name=. If there are no lines that start with $name=, then append a new line to file_path that is in the format $name="$value" using the uppercased value of $name
      if [[ $name == "null" ]]; then
        echo "$value" > "$file_path"
      else
        if ! grep -q "^$uppercase_name=" "$file_path" && [ "${file_path##*.}" == "env" ]; then
          echo "$uppercase_name=\"$value\"" >> "$file_path"
        fi
      fi

      # use the $name as an environment variable name and $value as the value to substitute
      # only when the uppercase name is not a comment
      if ! [ "${uppercase_name:0:1}" == "#" ]; then
        declare "$uppercase_name=$value"
        env -i "$uppercase_name=$value" envsubst '$'"$uppercase_name" < "$file_path" > "$file_path.tmp"
        unset "$uppercase_name"
        mv "$file_path.tmp" "$file_path"
      fi
    fi
  done
}

install_yq() {
  if command -v yq &> /dev/null; then
    return 0
  fi

  print_message "\ninstalling yq..."
  
  ARCH=$(uname -m)
  [[ $ARCH == "x86_64" ]] && ARCH="amd64"

  if [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "linux-musl"* ]]; then
    curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}" -o "$HOME/bin/yq"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_darwin_${ARCH}" -o "$HOME/bin/yq"
  else
    print_error_and_exit "unsupported operating system: $OSTYPE"
  fi

  chmod +x "$HOME/bin/yq"
  print_message "yq installed"
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

print_verbose_message () {
  if [ $VERBOSE == 1 ]; then
    echo -e "\e[3;22m\e[2m$1\e[0m"
  fi
}

print_message () {
  echo -e "\e[22m$1\e[0m"
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

project_containers () {
  fail_if_no_project $2
  fail_if_project_directory_does_not_exist "$1/$2"

  pushd $1/$2 > /dev/null
    docker compose -f compose.yaml ps
  popd > /dev/null
}

project_create () {
  local PROJECT_NAME="$1"
  local INSTALL_PATH="$2"
  local TEMPLATE_DIR="$3"
  local TEMPLATE_ID="$4"
  local LOCKER_YAML="$TEMPLATE_DIR/$TEMPLATE_ID/locker.yaml.template"

  fail_if_no_project $PROJECT_NAME
  fail_if_project_directory_exists "$INSTALL_PATH/$PROJECT_NAME"

  templates_pull "$TEMPLATES_DIR" "$TEMPLATES_URL"

  install_yq

  print_message "\nLet's get started building a new environment!"

  collect_user_inputs "$LOCKER_YAML"

  set_environment_overrides_or_defaults

  generate_from_template "$TEMPLATE_DIR" "$TEMPLATE_ID" "$INSTALL_PATH" "$PROJECT_NAME"
}

project_initiate () {
  local INSTALL_PATH="$1"
  local PROJECT_NAME="$2"
  local LOCKER_YAML="$INSTALL_PATH/$PROJECT_NAME/locker.yaml"

  print_message "\ninitiating project"

  pushd "$INSTALL_PATH/$PROJECT_NAME" > /dev/null
    
    # Read commands from locker.yaml.template
    local command_count=$(yq eval '.commands | length' "$LOCKER_YAML")
    
    # Only proceed if there are commands to execute
    if [ "$command_count" -gt 0 ]; then
      print_message "\nexecuting commands from template"
      
      # Execute each command
      for ((i=0; i<command_count; i++)); do
        local name=$(yq eval ".commands[$i].name" "$LOCKER_YAML")
        local command=$(yq eval ".commands[$i].command" "$LOCKER_YAML")
        local inputs=($(yq eval ".commands[$i].inputs[]?" "$LOCKER_YAML"))

        # create a local variable value that uses printf with the format and inputs to generate a dynamic value
        local command_args=()

        for input_key in "${inputs[@]}"; do
          local uppercase_key="${input_key^^}"
          command_args+=("${USER_INPUTS[$uppercase_key]}")
        done

        local value
        if [[ ${#command_args[@]} -gt 0 ]]; then
          command_with_subst=$(printf "$command" "${command_args[@]}")
        else
          command_with_subst="$command"  # No substitution needed
        fi

        print_verbose_message "--> $name ($command_with_subst)"
        
        # Execute the command
        bash -c "$command_with_subst"
      done
    fi
    
  popd > /dev/null

  print_message "\ninitiation complete"
}

project_remove () {
  fail_if_no_project "$2"
  fail_if_project_directory_does_not_exist "$1/$2"

  pushd "$1/$2" > /dev/null
    print_message "\nshutting down and removing containers"
    docker compose down -v
  popd > /dev/null

  print_message "\nremoving files and directory"
  rm -rf "$1/$2"
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
    while IFS= read -r FULL_PATH; do
      local PROJECT_NAME="$(basename ${FULL_PATH#${INSTALL_DIR}/})"
      
      print_message "\n\033[1m$FULL_PATH\033[0m"

      if [ -f "$FULL_PATH/locker.yaml" ]; then
        print_message "\e[1;35;3m$(head -n4 "$FULL_PATH/locker.yaml" | tail -n +2)\033[0m"
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

set_environment_overrides_or_defaults () {
  EMBEDDING_MODEL="${EMBEDDING_MODEL:-nomic-embed-text:latest}"
  DECISION_MODEL="${DECISION_MODEL:-qwen3:0.6b}"

  SECRET_KEY="${SECRET_KEY:-$(openssl rand -hex 32)}"

  POSTGRES_DB="${POSTGRES_DB:-owui$(openssl rand -hex 6)}"
  POSTGRES_HOST="${POSTGRES_HOST:-postgres}"
  POSTGRES_USER="${POSTGRES_USER:-user$(openssl rand -hex 6)}"
  POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -hex 12)}"

  DATABASE_URL="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST/$POSTGRES_DB"
  PGVECTOR_DB_URL="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST/$POSTGRES_DB"

  TIMEZONE="${TIMEZONE:-$(timedatectl status | grep "zone" | sed -e 's/^[ ]*Time zone: \(.*\) (.*)$/\1/g')}"

  HOST_PORT="${HOST_PORT:-${USER_INPUTS[HOST_PORT]:-3000}}"
  NGINX_HOST="${NGINX_HOST:-${USER_INPUTS[NGINX_HOST]:-localhost}}"
}

template_copy () {
  print_message "copying template $2"

  COPY_ID=$(uuidgen)

  cp -rf "$1/$2" "$1/$COPY_ID"

  print_message "created copy $COPY_ID"
}

templates_list () {
  pushd $1 > /dev/null
    while IFS= read -r FULL_PATH; do
      local UUID="$(basename ${FULL_PATH#${INSTALL_DIR}/})"
      
      print_message "\n\033[1m$FULL_PATH\033[0m"

      if [ -f "$UUID/locker.yaml.template" ]; then
        print_message "\e[1;35;3m$(head -n4 "$UUID/locker.yaml.template" | tail -n +2)\033[0m"
      fi
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
    print_verbose_message "\npulling latest templates"
    curl -fsSL $2 > templates.zip

    local SHABASE="$(basename $2)"

    mkdir -p --mode 750 ./unzip
    unzip -q templates.zip -d ./unzip

    while IFS= read -r FULL_PATH; do
      ITEM_NAME=$(basename $FULL_PATH)

      if !(diff $HOME/.starter-templates/$ITEM_NAME $FULL_PATH > /dev/null 2>&1); then
        print_verbose_message "\nupdating template $ITEM_NAME"
        rm -rf $HOME/.starter-templates/$ITEM_NAME
        cp -rf $FULL_PATH $HOME/.starter-templates/$ITEM_NAME
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

options=$(getopt -l "containers,copytemplate,create,nopull,projects,pull,remove,stop,start,template,templates,update,verbose,help" -o "cpruvh" -- "$@")
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
  project_create "$PROJECT_NAME" "$INSTALL_PATH" "$TEMPLATES_DIR" "$TEMPLATE_ID"
  project_initiate "$INSTALL_PATH" "$PROJECT_NAME"
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
