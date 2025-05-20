#!/bin/sh

echo "--- Debugging entrypoint.sh ---"
echo "User: $(whoami)"
echo "HOME: $HOME"
echo "DOCKER_CONFIG: $DOCKER_CONFIG"

echo "Checking for Docker config in $HOME/.docker:"
if [ -f "$HOME/.docker/config.json" ]; then
  echo "$HOME/.docker/config.json exists."
  if grep -q '\"auths\":' "$HOME/.docker/config.json"; then
    echo "$HOME/.docker/config.json appears to contain an 'auths' section."
  else
    echo "$HOME/.docker/config.json does NOT appear to contain an 'auths' section."
  fi
else
  echo "$HOME/.docker/config.json not found."
fi

if [ -n "$DOCKER_CONFIG" ] && [ "$DOCKER_CONFIG" != "$HOME/.docker" ]; then # Also check DOCKER_CONFIG if it's different
  echo "Checking for Docker config in $DOCKER_CONFIG (from DOCKER_CONFIG env var):"
  if [ -f "$DOCKER_CONFIG/config.json" ]; then
    echo "$DOCKER_CONFIG/config.json exists."
    if grep -q '\"auths\":' "$DOCKER_CONFIG/config.json"; then
      echo "$DOCKER_CONFIG/config.json appears to contain an 'auths' section."
    else
      echo "$DOCKER_CONFIG/config.json does NOT appear to contain an 'auths' section."
    fi
  else
    echo "$DOCKER_CONFIG/config.json not found."
  fi
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
