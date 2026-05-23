#!/bin/bash

WORKING_DIR=""
cd $WORKING_DIR

# comparing the local repository with the remote repository and deploying updates if there are any changes
git pull > pull_stat
PULL_STAT=$(cat pull_stat | grep "Updating")
if [ ! -z "$PULL_STAT" ]; then
    # if there are changes, deploy the updates to the web server and reload the Apache service
    echo "New changes detected. Deploying updates..."
    rm pull_stat
    rsync -av --delete $WORKING_DIR/ /var/www/html/
    systemctl reload httpd.service
    systemctl restart httpd.service
else
    # if there are no changes, print a message and exit
    echo "No changes detected. Deployment not required."
fi