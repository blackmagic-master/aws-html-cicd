#!/bin/bash

KEY_FILE=$1
CONFIG_FILE=$2
PUBLIC_IP=$3
WORKING_DIR="$(cat "$CONFIG_FILE" | jq -r '.git_repo .repo_path')"
PRIVATE_KEY_FILE=$4
REPO_URL="$(cat "$CONFIG_FILE" | jq -r '.git_repo .repo_url')"
PROVISION_SCRIPT_FILE=$5

scp -i "$KEY_FILE" "$PROVISION_SCRIPT_FILE" ec2-user@$PUBLIC_IP:/tmp/provision_script.sh

ssh -i "$KEY_FILE" ec2-user@$PUBLIC_IP << EOF
    sudo su
    chmod +x /tmp/provision_script.sh
    /tmp/provision_script.sh
EOF

scp -i "$KEY_FILE" "$PRIVATE_KEY_FILE" ec2-user@$PUBLIC_IP:~/.ssh/id_rsa

ssh -i "$KEY_FILE" ec2-user@$PUBLIC_IP << EOF
    sudo su
    cp /home/ec2-user/.ssh/id_rsa /root/.ssh/id_rsa
    chmod 600 ~/.ssh/id_rsa
    ssh-keyscan github.com >>~/.ssh/known_hosts
    git config --global user.name "$( cat "$CONFIG_FILE" | jq -r '.git_repo .user_name' )"
    git config --global user.email "$( cat "$CONFIG_FILE" | jq -r '.git_repo .user_email' )"
    git clone "$REPO_URL" "$WORKING_DIR"
    git config --global --add safe.directory $WORKING_DIR
    cp -r "$WORKING_DIR"/* /var/www/html/
    find /var/www/ -type f -exec chmod 664 {} \;
    find /var/www/ -type d -exec chmod 775 {} \;
    find /var/www/ -type d -exec chmod g+s {} \;
    systemctl reload httpd.service
    systemctl restart httpd.service
EOF