#!/bin/bash
# This script is used to provision the EC2 instance with necessary software and configurations.

sudo su

# updating the system
yum update -y

# installing and configuring Apache web server
yum install -y httpd
systemctl start httpd.service
systemctl enable httpd.service

# installing and configuring cron for scheduled tasks
yum install cronie -y
systemctl enable crond.service
systemctl start crond.service

# installing git for version control
yum install -y git