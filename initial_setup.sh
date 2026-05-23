# credentials for AWS CLI
#export AWS_ACCESS_KEY_ID="your_access_key_id"
#export AWS_SECRET_ACCESS_KEY="your_secret_access_key"
#export AWS_DEFAULT_REGION="us-east-1"

# global variables
PROJECT_NAME="aws-http-cicd"

# VPC configuration variables
VPC_CIDR="172.25.1.0/24"
VPC_NAME="$PROJECT_NAME-vpc"
SUBNET_CIDR="172.25.1.0/26"
SUBNET_NAME="$PROJECT_NAME-subnet"
AVAILABILITY_ZONE="$(aws ec2 describe-availability-zones \
| jq -r '.[] .[] .ZoneName' | head -1)"
IGW_NAME="$PROJECT_NAME-igw"
RT_NAME="$PROJECT_NAME-rt"
DESTINATION_CIDR="0.0.0.0/0"

# security group configuration variables
SG_NAME="$PROJECT_NAME-sg"
SG_DESCRIPTION="Security group for $PROJECT_NAME"
ports=(22 80 443)

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
}

cleanup(){
    echo "Cleaning up resources..."
    aws ec2 delete-security-group --group-id "$SG_ID" >> /dev/null
    aws ec2 delete-route --route-table-id "$RT_ID" --destination-cidr-block "$DESTINATION_CIDR" >> /dev/null
    aws ec2 disassociate-route-table --association-id "$ASSOCIATION_ID"
    aws ec2 delete-route-table --route-table-id "$RT_ID"
    aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
    aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID"
    aws ec2 delete-subnet --subnet-id "$SUBNET_ID"
    aws ec2 delete-vpc --vpc-id "$VPC_ID"
}

# main function to run the setup
main(){
    aws_checker
    create_vpc
    create_subnet
    create_igw
    create_rt
    create_sg
    cleanup
}

# run the main function
main
