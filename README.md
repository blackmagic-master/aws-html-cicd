# aws-html-cicd

## Overview

This repository contains a simple CI/CD tool for deploying an HTML website to an AWS EC2 instance. The project creates the required AWS infrastructure, provisions an EC2 instance with Apache and Git, clones a Git repository, and configures a periodic deployment job.

## Prerequisites

- AWS CLI installed and configured
- `jq` installed
- A Git repository with your HTML website accessible via SSH
- A valid private key for GitHub stored locally and referenced in `config.json`
- A `key.pem` private key file present locally and matching the GitHub configuration so repos can be accessed

## Files

- `initial_setup.sh` — main script to create AWS resources and initialize deployment
- `src/provision_script.sh` — EC2 instance provisioning script
- `src/git_config.sh` — configures Git on the EC2 instance and sets up deployment
- `src/script.sh` — deployment script run by cron on the EC2 instance
- `config.json` — configuration file for AWS, EC2, and Git settings

## How to change the config file

Update `config.json` with your project-specific values.

Key sections:

- `global`
  - `project_name`: project prefix used for resource names
  - `region`: AWS region for resource creation
  - `aws_access_key` and `aws_secret_key`: AWS credentials used by the script

- `vpc`
  - `cidr_block`: VPC CIDR range
  - `subnet_cidr_block`: subnet CIDR range
  - `destination_cidr_block`: internet route range, usually `0.0.0.0/0`

- `ec2`
  - `ami_id`: AMI used for the EC2 instance
  - `instance_type`: EC2 instance type
  - `instance_count`: number of instances to create
  - `ami_user_name`: SSH user name for the instance (for Amazon Linux this is usually `ec2-user`)

- `git_repo`
  - `repo_path`: path on EC2 where the repo is cloned
  - `user_name`: Git user.name for Git config
  - `user_email`: Git user.email for Git config
  - `private_key_file`: local path to the SSH private key for accessing the repository
  - `repo_url`: SSH URL of your Git repository

Example edit:

```json
"git_repo": {
    "repo_path": "/opt/git-repo",
    "user_name": "your-github-username",
    "user_email": "your-github-email",
    "private_key_file": "key.pem",
    "repo_url": "git@github.com:your-github-username/github-repo.git"
}
```

## Usage

1. Make sure `config.json` is updated with the correct AWS and Git settings.
2. Run the setup script:

```bash
./initial_setup.sh init
```

3. After setup completes, the web server will be available at the public IP shown in the output.
4. To remove all created AWS resources, run:

```bash
./initial_setup.sh cleanup
```

## Notes

- The deployment job runs every 5 minutes via cron and pulls updates from the configured Git repository.
- The cloned website content is synced to `/var/www/html` on the EC2 instance.

## Author

BlackMagic Master
Szymon G.