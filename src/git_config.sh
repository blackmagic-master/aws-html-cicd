#!/bin/bash

# variables passed as arguments
KEY_FILE=$1
CONFIG_FILE=$2
PUBLIC_IP=$3
PRIVATE_KEY_FILE=$4
PROVISION_SCRIPT_FILE=$5

# variables extracted from config file
WORKING_DIR="$(cat "$CONFIG_FILE" | jq -r '.git_repo .repo_path')"
REPO_URL="$(cat "$CONFIG_FILE" | jq -r '.git_repo .repo_url')"
USER_NAME="$(cat "$CONFIG_FILE" | jq -r '.ec2 .ami_user_name' )"
GIT_SCRIPT_FILE="src/script.sh"

# cron job configuration
croncmd="*/5 * * * * /opt/script.sh"

# copying the provisioning script to the EC2 instance and executing it
provisioning(){
    ssh-keyscan $PUBLIC_IP >>~/.ssh/known_hosts
    scp -i "$KEY_FILE" "$PROVISION_SCRIPT_FILE" $USER_NAME@$PUBLIC_IP:/tmp/provision_script.sh
    ssh -i "$KEY_FILE" $USER_NAME@$PUBLIC_IP << EOF
        sudo su
        chmod +x /tmp/provision_script.sh
        /tmp/provision_script.sh
EOF
}

# copying the private key to the EC2 instance and configuring git
configuring(){
    scp -i "$KEY_FILE" "$PRIVATE_KEY_FILE" $USER_NAME@$PUBLIC_IP:~/.ssh/id_rsa
    ssh -i "$KEY_FILE" $USER_NAME@$PUBLIC_IP << EOF
        sudo su
        cp /home/$USER_NAME/.ssh/id_rsa /root/.ssh/id_rsa
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
}

# copying the deployment script to the EC2 instance and setting up a cron job for it
setting_cron(){
    scp -i "$KEY_FILE" "$GIT_SCRIPT_FILE" $USER_NAME@$PUBLIC_IP:/tmp/script.sh
    ssh -i "$KEY_FILE" $USER_NAME@$PUBLIC_IP << EOF
        sudo su
        sed -i "0,/WORKING_DIR=\"\"/s|WORKING_DIR=\"\"|WORKING_DIR=\"$WORKING_DIR\"|" /tmp/script.sh 
        mv /tmp/script.sh /opt/script.sh
        chmod +x /opt/script.sh
        (crontab -l 2>/dev/null; echo "$croncmd") | crontab -
EOF
}

main(){
    provisioning
    configuring
    setting_cron
    echo "Git repository configured and deployment script set up successfully."

}

main