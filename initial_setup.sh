#!/bin/bash
# configuration file for AWS infrastructure setup
CONFIG_FILE="config.json"

# credentials for AWS CLI
export AWS_ACCESS_KEY_ID="$(cat "$CONFIG_FILE" | jq -r '.global .aws_access_key')"
export AWS_SECRET_ACCESS_KEY="$(cat "$CONFIG_FILE" | jq -r '.global .aws_secret_key')"
export AWS_DEFAULT_REGION="$(cat "$CONFIG_FILE" | jq -r '.global .region')"

# global variables
PROJECT_NAME="$(cat "$CONFIG_FILE" | jq -r '.global .project_name')"

# VPC configuration variables
VPC_CIDR="$(cat "$CONFIG_FILE" | jq -r '.vpc .cidr_block')"
VPC_NAME="$PROJECT_NAME-vpc"
SUBNET_CIDR="$(cat "$CONFIG_FILE" | jq -r '.vpc .subnet_cidr_block')"
SUBNET_NAME="$PROJECT_NAME-subnet"
AVAILABILITY_ZONE="$(aws ec2 describe-availability-zones \
| jq -r '.[] .[] .ZoneName' | head -1)"
IGW_NAME="$PROJECT_NAME-igw"
RT_NAME="$PROJECT_NAME-rt"
DESTINATION_CIDR="$(cat "$CONFIG_FILE" | jq -r '.vpc .destination_cidr_block')"

# security group configuration variables
SG_NAME="$PROJECT_NAME-sg"
SG_DESCRIPTION="Security group for $PROJECT_NAME"
ports=(22 80 443)
KEY_NAME="$PROJECT_NAME-key"
KEY_FILE="$KEY_NAME.pem"

# EC2 instance configuration variables
AMI_ID="$(cat "$CONFIG_FILE" | jq -r '.ec2 .ami_id')"
INSTANCE_TYPE="$(cat "$CONFIG_FILE" | jq -r '.ec2 .instance_type')"
INSTANCE_NAME="$PROJECT_NAME-instance"
INSTANCE_COUNT=$(cat "$CONFIG_FILE" | jq -r '.ec2 .instance_count')
PROVISION_SCRIPT_FILE="src/provision_script.sh"
GIT_SCRIPT_FILE="src/git_config.sh"
GIT_PRIVATE_KEY_FILE="$(cat "$CONFIG_FILE" | jq -r '.git_repo .private_key_file')"

# checking if AWS CLI is installed
aws_checker(){
    local aws_path=$(which aws)
    if [ -z "$aws_path" ]; then
        echo "AWS CLI is not installed. Please install it to proceed."
        exit 1
    fi
}

# creating a new VPC and checking if it already exists
create_vpc(){
    echo "Creating a new VPC..."
    for cidr_block in "$(aws ec2 describe-vpcs \
    | jq -r ' .[] .[] .CidrBlockAssociationSet .[] .CidrBlock')"; do
        if [ "$cidr_block" == "$VPC_CIDR" ]; then
            echo "A VPC with CIDR block $VPC_CIDR already exists."
            exit 1
        fi
    done
    VPC_ID=$(aws ec2 create-vpc --cidr-block "$VPC_CIDR" \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$VPC_NAME}]" \
    |  jq -r '.[] .VpcId' )
    echo "VPC created with ID: $VPC_ID"
    aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support
    aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames
}

# creating a new subnet
create_subnet(){
    echo "Creating a new subnet..."
    SUBNET_ID="$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block "$SUBNET_CIDR" \
  --availability-zone "$AVAILABILITY_ZONE" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$SUBNET_NAME}]" \
  | jq -r '.[] .SubnetId')"
    echo "Subnet created with ID: $SUBNET_ID"
}

# creating a new Internet Gateway
create_igw(){
    echo "Creating a new Internet Gateway..."
    IGW_ID="$(aws ec2 create-internet-gateway \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$IGW_NAME}]" \
  | jq -r '.[] .InternetGatewayId')"
    echo "Internet Gateway created with ID: $IGW_ID"
    aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
}

create_rt(){
    echo "Creating a new Route Table..."
    RT_ID="$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$RT_NAME}]" \
  | jq -r '.[] .RouteTableId' 2> /dev/null)"
    echo "Route Table created with ID: $RT_ID"
    aws ec2 create-route --route-table-id "$RT_ID" \
    --destination-cidr-block "$DESTINATION_CIDR" --gateway-id "$IGW_ID" >> /dev/null
    ASSOCIATION_ID=$(aws ec2 associate-route-table --route-table-id "$RT_ID" \
    --subnet-id "$SUBNET_ID" | jq -r '.AssociationId')
    echo "Route Table associated with Subnet. Association ID: $ASSOCIATION_ID"
    aws ec2 modify-subnet-attribute \
    --subnet-id $SUBNET_ID --map-public-ip-on-launch >> /dev/null
}

create_sg(){
    SG_ID=$(aws ec2 create-security-group \
  --group-name "$SG_NAME" \
  --description "$SG_DESCRIPTION" \
  --vpc-id "$VPC_ID" | jq -r '.GroupId')
    echo "Security Group created with ID: $SG_ID"
    for port in "${ports[@]}"; do
        aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" --protocol tcp \
        --port "$port" --cidr $DESTINATION_CIDR >> /dev/null
        echo "Ingress rule added for port $port"
    done
    aws ec2 create-key-pair --key-name "$KEY_NAME" --query 'KeyMaterial' --output text > "$KEY_FILE"
    chmod 400 "$KEY_FILE"
    echo "Key pair created with name: $KEY_NAME and saved to $KEY_FILE"
}

create_vm(){
    local provision_script=$(<"$PROVISION_SCRIPT_FILE")
    echo "Creating a new EC2 instance..."
    INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --count $INSTANCE_COUNT \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $SG_ID \
    --subnet-id $SUBNET_ID \
    --associate-public-ip-address \
    --user-data "$provision_script" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    | jq -r '.Instances[] .InstanceId')
    echo "EC2 instance created with ID: $INSTANCE_ID"
    echo "Waiting for the instance to be in 'running' state..."
    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
    echo "Instance is running. Fetching public IP address..."
    PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
    | jq -r '.Reservations[] .Instances[] .PublicIpAddress')
    echo "Instance Public IP: $PUBLIC_IP"
}

cleanup(){
    echo "Cleaning up resources..."
    aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --force --skip-os-shutdown >> /dev/null
    aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"
    rm -f "$KEY_FILE"
    aws ec2 delete-key-pair --key-name "$KEY_NAME" >> /dev/null
    aws ec2 delete-security-group --group-id "$SG_ID" >> /dev/null
    aws ec2 delete-route --route-table-id "$RT_ID" --destination-cidr-block "$DESTINATION_CIDR" >> /dev/null
    aws ec2 disassociate-route-table --association-id "$ASSOCIATION_ID" >> /dev/null
    aws ec2 delete-route-table --route-table-id "$RT_ID" >> /dev/null
    aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" >> /dev/null
    aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" >> /dev/null
    aws ec2 delete-subnet --subnet-id "$SUBNET_ID" >> /dev/null
    aws ec2 delete-vpc --vpc-id "$VPC_ID" >> /dev/null
    echo "All resources have been cleaned up."
}

git_init(){
    $GIT_SCRIPT_FILE $KEY_FILE $CONFIG_FILE $PUBLIC_IP $GIT_PRIVATE_KEY_FILE $PROVISION_SCRIPT_FILE
}

# main function to run the setup
main(){
    aws_checker
    create_vpc
    create_subnet
    create_igw
    create_rt
    create_sg
    create_vm
    git_init
    echo "Setup complete. You can access the web server at http://$PUBLIC_IP"
    read -p "Press Enter to terminate the instance and clean up resources..."
    read -p "Are you sure you want to clean up resources?"
    cleanup
}

# run the main function
main
