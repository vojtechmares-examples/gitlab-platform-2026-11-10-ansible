#!/usr/bin/env bash
# Set every CI/CD variable this project needs, with the GitLab CLI (glab). Safe to run again.
#
#   export ANSIBLE_SSH_KEY_FILE=path/to/private-key-of-the-ansible-user
#   export DEPLOY_PUBLIC_KEY_FILE=path/to/public-key-of-the-deploy-user
#   export SECRETS_FILE=path/to/secrets.env      # DB_PASSWORD_<APP>_<ENV>=...; created when missing
#   glab auth login --hostname gitlab.maresdemo.com   # once
#   scripts/set-ci-variables.sh
#
# Passwords are generated here (openssl) the first time and kept in SECRETS_FILE, outside the repository,
# so the same values can be given to the application projects that connect to the databases.
set -euo pipefail

HOST="${GITLAB_HOST:-gitlab.maresdemo.com}"
PROJECT="${PROJECT:-examples/ansible}"
APPS=(DOTNET_API JAVA_SYSTEMD JAVA_CONTAINER)
ENVS=(staging production)

: "${ANSIBLE_SSH_KEY_FILE:?path to the private key of the ansible user}"
: "${DEPLOY_PUBLIC_KEY_FILE:?path to the public key of the deploy user}"
: "${SECRETS_FILE:?path of the secrets file (created when it does not exist)}"

export GITLAB_HOST="${HOST}"   # glab reads GITLAB_HOST; be explicit so it never talks to another instance
set_var() { glab variable set "$@" --repo "${HOST}/${PROJECT}" >/dev/null; }

if [ ! -f "${SECRETS_FILE}" ]; then
  umask 077
  for app in "${APPS[@]}"; do
    for env in "${ENVS[@]}"; do
      printf 'DB_PASSWORD_%s_%s=%s\n' "${app}" "$(tr '[:lower:]' '[:upper:]' <<<"${env}")" "$(openssl rand -hex 20)"
    done
  done >"${SECRETS_FILE}"
  echo "generated ${SECRETS_FILE}"
fi

echo "==> ${PROJECT} on ${HOST}"

# The key the pipeline logs in with. File type: the variable holds the path of a temporary file.
# Protected: only pipelines on protected branches and tags get it.
set_var ANSIBLE_SSH_PRIVATE_KEY --type file --protected --description "Private key of the ansible user on the deploy server" \
  --value "$(cat "${ANSIBLE_SSH_KEY_FILE}")"$'\n'

set_var DEPLOY_PUBLIC_KEY --value "$(cat "${DEPLOY_PUBLIC_KEY_FILE}")" --description "Public key of the deploy user (authorised for the rootless Podman account)"
set_var EXAMPLES_DOMAIN --value "${EXAMPLES_DOMAIN:-examples.maresdemo.com}" --description "Parent domain of the example applications"

# One password per application and environment. The same variable name is set twice with a different
# environment scope, so a job in the environment "staging" sees the staging password.
for app in "${APPS[@]}"; do
  for env in "${ENVS[@]}"; do
    key="DB_PASSWORD_${app}_$(tr '[:lower:]' '[:upper:]' <<<"${env}")"
    value="$(grep -E "^${key}=" "${SECRETS_FILE}" | cut -d= -f2-)"
    [ -n "${value}" ] || { echo "missing ${key} in ${SECRETS_FILE}" >&2; exit 1; }
    set_var "DB_PASSWORD_${app}" --value "${value}" --scope "${env}" --masked --protected \
      --description "Password of the ${app} database role in ${env}"
  done
done

echo "variables of ${PROJECT}:"
glab variable list --repo "${HOST}/${PROJECT}" | awk 'NR>1 {print "  " $1, $3, $4}' | head -30
