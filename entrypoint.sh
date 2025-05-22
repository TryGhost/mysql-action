#!/bin/sh

# # Attempt Docker login if credentials are provided
# if [ -n "$INPUT_DOCKER_USERNAME" ] && [ -n "$INPUT_DOCKER_PASSWORD_OR_TOKEN" ]; then
#   echo "Attempting Docker login with provided credentials..."
#   # The `docker login` command expects the password on stdin.
#   # We use a HEREDOC to pass the password securely without echoing it to the logs if possible.
#   # However, the act of using it as an env var means it's less secure than direct secret handling by a dedicated login action.
#   echo "$INPUT_DOCKER_PASSWORD_OR_TOKEN" | docker login -u "$INPUT_DOCKER_USERNAME" --password-stdin
#   if [ $? -ne 0 ]; then
#     echo "Docker login FAILED. Please check the provided docker_username and docker_password_or_token."
#     echo "Proceeding without explicit login, which may lead to pull failures if the image is private or rate limits are hit."
#     # Consider exiting if login is critical: exit 1
#   else
#     echo "Docker login successful."
#   fi
# else
#   echo "Docker username/password not provided; skipping explicit login."
#   echo "Relying on existing Docker client configuration or anonymous access."
# fi

echo "$(pwd)"

# We can remove the extensive DOCKER_CONFIG debugging now as we control the login explicitly.
echo "--- Proceeding to MySQL Setup ---"

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
