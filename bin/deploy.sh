#!/bin/bash

# Get folder of the current script.
WORKDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BRANCH="$(git symbolic-ref HEAD 2>/dev/null)" ||
BRANCH="(unnamed branch)"     # detached HEAD
BRANCH=${BRANCH##refs/heads/}
SKIP_STOP_TRAFFIC=false
SKIP_ASSETS_PRECOMPILE=false

USER="$(id -un)"
GROUP="$(id -gn $USER)"

log() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@"
}

err() {
  log "[Error] $@"
  exit 1
}

free_workdir() {
  # Free workdir permissions
  sudo chmod -R 777 $WORKDIR
  # Setup current user and group
  sudo chown -R $USER:$GROUP $WORKDIR
}

lock_folder() {
  find $1 -type d -exec sudo chmod 700 {} \;
  find $1 -type f -exec sudo chmod 600 {} \;
  sudo chown -R $USER:$GROUP $1
}

lock_workdir() {
  # Set www-data user
  sudo chown -R www-data:www-data $WORKDIR
  # Setup folder permissions
  find $WORKDIR -type d -exec sudo chmod 755 {} +
  # Setup file permissions
  find $WORKDIR -type f -exec sudo chmod 644 {} +
  # Lock .git/ folder permissions
  lock_folder $WORKDIR/.git/
  # Lock bin/ folder
  lock_folder $WORKDIR/bin/
  # Lock config/*.yml files
  sudo chmod 600 $WORKDIR/config/*.yml
  # Set deploy script executable permissions
  sudo chmod +x $WORKDIR/deploy.sh
}

stop_server() {
  if [[ `ps -acx|grep nginx|wc -l` > 0 ]]; then # if nginx is active, stop it
    log "Stopping Nginx to precompile."
    sudo service nginx stop
  fi
}

start_server() {
  if [[ `ps -acx|grep nginx|wc -l` > 0 ]]; then # if nginx is active, restart it
    log "Reiniciando Nginx."
    sudo service nginx restart
  else # if not, start it
    log "Iniciando Nginx."
    sudo service nginx start
  fi
}

print_help() {
  echo ""
  echo "Usage: $0 [OPTION]..."
  echo "Download the latest version of the project from the remote repository,"
  echo "precompile and set permissions for production."
  echo ""
  echo -e "\t-b,  --branch=BRANCH \t\t Sets the repository branch. Default: $BRANCH"
  echo -e "\t-h,  --help \t\t\t Display this help and exit."
  echo -e "\t-p,  --skip_assets_precompile \t Skip the step to precompile the assets. Default: $SKIP_ASSETS_PRECOMPILE"
  echo -e "\t-s,  --skip_stop_traffic \t Skip the step to stop Nginx when precompiling"
  echo -e "\t\t\t\t\t (Avoid permission errors). Default: $SKIP_STOP_TRAFFIC"
  echo ""
  echo "By default this script will save local changes with the 'git stash' command"
  echo "and download the latest change from the remote repository. It will then stop"
  echo "Nginx to prevent further cache files from being created to avoid permission"
  echo "errors. Later, it will change the permissions of the entire project folder to"
  echo "777 and ownership to the current user, and then precompile the assets. Lastly,"
  echo "set the correct permissions for production and restart Nginx."
  echo ""
  echo "Created by Jesus Magallon <jesus.magallon@villagroup.com>"
  echo "Copyright (c) The Villa Group Resorts 2022"
  echo ""
}

while [ $# -gt 0 ]; do
  case "$1" in
    --branch*|-b*)
      if [[ "$1" != *=* ]]; then shift; fi # Value is next arg if no `=`
      BRANCH="${1#*=}"
    ;;
    --skip_stop_traffic|-s)
      SKIP_STOP_TRAFFIC=true
    ;;
    --skip_assets_precompile|-p)
      SKIP_ASSETS_PRECOMPILE=true
    ;;
    --help|-h)
      print_help
      exit 0
    ;;
    *)
      >&2 log "[Error] Invalid argument."
      print_help
      exit 1
    ;;
  esac
  shift
done

echo "BRANCH: $BRANCH"
echo "SKIP_STOP_TRAFFIC: $SKIP_STOP_TRAFFIC"
echo "SKIP_ASSETS_PRECOMPILE: $SKIP_ASSETS_PRECOMPILE"

if [ ! -d "${WORKDIR}" ]; then
  err "$WORKDIR folder does not exist."
fi

log "Moving to the project directory ($WORKDIR)."
cd $WORKDIR

STASH_MESSAGE=$(git stash)
log $STASH_MESSAGE

log "Pulling from the remote repository."
git pull origin $BRANCH
if [ $? -ne 0 ]; then
  lock_workdir
  err "Failed to update local repository."
fi

if [ "$SKIP_ASSETS_PRECOMPILE" = false ]; then
  if [ "$SKIP_STOP_TRAFFIC" = false ]; then
    stop_server
  fi

  free_workdir

  log "Cleaning the assets."
  RAILS_ENV=production bundle exec rake assets:clean
  if [ $? -ne 0 ]; then
    lock_workdir
    err 'Asset cleanup failed, please fix the error and try again.' 'One possible solution is to stop traffic, try running the command without the "--skip_stop_traffic" and "-s" flags.'
  fi

  free_workdir

  log "Precompiling assets."
  RAILS_ENV=production bundle exec rake assets:precompile
  if [ $? -ne 0 ]; then
    lock_workdir
    err 'Asset precompile failed, please fix the error and try again.' 'One possible solution is to stop traffic, try running the command without the "--skip_stop_traffic" and "-s" flags.'
  fi
fi

lock_workdir

if [ "$SKIP_STOP_TRAFFIC" = false ]; then
  start_server
else
  log "Restarting Passenger."
  sudo touch $WORKDIR/tmp/restart.txt
fi

log "Exit..."
echo "Last deployment: $(date +'%d/%m/%Y %H:%M:%S %z')" > $WORKDIR/last_deployment.txt
exit 1
