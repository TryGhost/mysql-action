#!/bin/sh

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

if ! sh -c "$docker_run"; then
  echo "Failed to start MySQL container"
  exit 1
fi

MAX_TRIES=120
TRIES=0
while ! docker exec mysql mysql -h"127.0.0.1" -P"$INPUT_HOST_PORT" -u"$HEALTHCHECK_USER" -p"$HEALTHCHECK_PASS" -e "SELECT 1" $INPUT_MYSQL_DATABASE &> /dev/null; do
    TRIES=$((TRIES + 1))
    if [ "$TRIES" -ge "$MAX_TRIES" ]; then
      echo "MySQL failed to start after ${MAX_TRIES}s"
      docker logs mysql 2>&1 || true
      exit 1
    fi
    if ! docker inspect --format='{{.State.Running}}' mysql 2>/dev/null | grep -q true; then
      echo "MySQL container is not running"
      docker logs mysql 2>&1 || true
      exit 1
    fi
    echo "MySQL is unavailable - sleeping ($TRIES/$MAX_TRIES)"
    sleep 1
done

echo "MySQL is available"
