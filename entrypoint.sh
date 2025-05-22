#!/bin/sh

echo "--- Debugging entrypoint.sh ---"
echo "User: $(whoami)"
echo "HOME_DIR: $HOME"
echo "DOCKER_CONFIG_ENV: $DOCKER_CONFIG" # Value of the DOCKER_CONFIG environment variable itself

CONFIG_PATH_TO_CHECK=""

if [ -n "$DOCKER_CONFIG" ]; then
  echo "DOCKER_CONFIG environment variable is set to: '$DOCKER_CONFIG'"
  CONFIG_PATH_TO_CHECK="$DOCKER_CONFIG/config.json"
elif [ -n "$HOME" ]; then # Fallback to HOME if DOCKER_CONFIG is not set
  echo "DOCKER_CONFIG env var not set, checking default location: '$HOME/.docker/config.json'"
  CONFIG_PATH_TO_CHECK="$HOME/.docker/config.json"
else
  echo "CRITICAL: DOCKER_CONFIG env var is not set AND HOME directory is not set. Cannot determine Docker config path."
fi

if [ -n "$CONFIG_PATH_TO_CHECK" ]; then
  echo "Effective Docker config file path being checked: '$CONFIG_PATH_TO_CHECK'"
  if [ -f "$CONFIG_PATH_TO_CHECK" ]; then
    echo "SUCCESS: Docker config file '$CONFIG_PATH_TO_CHECK' exists."
    if grep -q '\"auths\":' "$CONFIG_PATH_TO_CHECK"; then
      echo "INFO: '$CONFIG_PATH_TO_CHECK' appears to contain an 'auths' section (good sign)."
    else
      echo "WARNING: '$CONFIG_PATH_TO_CHECK' does NOT appear to contain an 'auths' section."
    fi
  else
    echo "FAILURE: Docker config file '$CONFIG_PATH_TO_CHECK' not found at this path inside the container."
  fi
else
  echo "CRITICAL: Could not determine a Docker config.json path to check."
fi
echo "--- End Debugging ---"

docker_run="docker run"

if [ "$INPUT_USE_TMPFS" == "true" ]; then
  echo "Using tmpfs"
  docker_run="$docker_run --tmpfs /var/lib/mysql:rw,noexec,nosuid,size=$INPUT_TMPFS_SIZE"
fi

HEALTHCHECK_USER=""
HEALTHCHECK_PASS=""

if [ -n "$INPUT_MYSQL_ROOT_PASSWORD" ]; then
  echo "Root password not empty, use root superuser"

  HEALTHCHECK_USER="root"
  HEALTHCHECK_PASS="$INPUT_MYSQL_ROOT_PASSWORD"

  docker_run="$docker_run -e MYSQL_ROOT_PASSWORD=$INPUT_MYSQL_ROOT_PASSWORD"
elif [ -n "$INPUT_MYSQL_USER" ]; then
  if [ -z "$INPUT_MYSQL_PASSWORD" ]; then
    echo "The mysql password must not be empty when mysql user exists"
    exit 1
  fi

  echo "Use specified user and password"

  HEALTHCHECK_USER="$INPUT_MYSQL_USER"
  HEALTHCHECK_PASS="$INPUT_MYSQL_PASSWORD"

  docker_run="$docker_run -e MYSQL_RANDOM_ROOT_PASSWORD=true -e MYSQL_USER=$INPUT_MYSQL_USER -e MYSQL_PASSWORD=$INPUT_MYSQL_PASSWORD"
else
  echo "Both root password and superuser are empty, must contains one superuser"
  exit 1
fi

if [ -n "$INPUT_MYSQL_DATABASE" ]; then
  echo "Use specified database"

  docker_run="$docker_run -e MYSQL_DATABASE=$INPUT_MYSQL_DATABASE"
fi

docker_run="$docker_run -d --name mysql -p $INPUT_HOST_PORT:$INPUT_CONTAINER_PORT mysql:$INPUT_MYSQL_VERSION --port=$INPUT_CONTAINER_PORT"
docker_run="$docker_run --character-set-server=$INPUT_CHARACTER_SET_SERVER --collation-server=$INPUT_COLLATION_SERVER --default-authentication-plugin=$INPUT_AUTHENTICATION_PLUGIN"

sh -c "$docker_run"

while ! docker exec mysql mysql -h"127.0.0.1" -P"$INPUT_HOST_PORT" -u"$HEALTHCHECK_USER" -p"$HEALTHCHECK_PASS" -e "SELECT 1" $INPUT_MYSQL_DATABASE &> /dev/null; do
    echo "MySQL is unavailable - sleeping"
    sleep 1
done

echo "MySQL is available"
