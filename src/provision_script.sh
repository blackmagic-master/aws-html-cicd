#!/bin/bash
# This script is used to provision the EC2 instance with necessary software and configurations.
sudo su
yum update -y
yum install -y httpd
systemctl start httpd.service
systemctl enable httpd.service
yum install -y git