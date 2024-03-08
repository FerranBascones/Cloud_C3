export WOF_AWS_REGION=us-east-1 
export WOF_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
export WOF_ECS_CLUSTER_NAME=ecs-fargate-wordpress
export WOF_CFN_STACK_NAME=WordPress-on-Fargate

wget https://raw.githubusercontent.com/aws-samples/containers-blog-maelstrom/main/CloudFormation/wordpress-ecs-fargate.yaml

aws cloudformation create-stack \
  --stack-name $WOF_CFN_STACK_NAME \
  --region $WOF_AWS_REGION \
  --template-body file://wordpress-ecs-fargate.yaml
  
# afegir time
aws cloudformation wait stack-create-complete \
  --stack-name $(aws cloudformation describe-stacks  \
    --region $WOF_AWS_REGION \
    --stack-name $WOF_CFN_STACK_NAME \
    --query 'Stacks[0].StackId' --output text) \
  --region $WOF_AWS_REGION
  
export WOF_EFS_FS_ID=$(aws cloudformation describe-stacks  \
  --region $WOF_AWS_REGION \
  --stack-name $WOF_CFN_STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='EFSFSId'].OutputValue" \
  --output text)
export WOF_EFS_AP=$(aws cloudformation describe-stacks  \
  --region $WOF_AWS_REGION \
  --stack-name $WOF_CFN_STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='EFSAccessPoint'].OutputValue" \
  --output text)
export WOF_RDS_ENDPOINT=$(aws cloudformation describe-stacks  \
  --region $WOF_AWS_REGION \
  --stack-name $WOF_CFN_STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='RDSEndpointAddress'].OutputValue" \
  --output text)
export WOF_VPC_ID=$(aws cloudformation describe-stacks  \
  --region $WOF_AWS_REGION \
  --stack-name $WOF_CFN_STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='VPCId'].OutputValue" \
  --output text)
export WOF_PUBLIC_SUBNET0=$(aws cloudformation describe-stacks  \
  --region $WOF_AWS_REGION \
  --stack-name $WOF_CFN_STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='PublicSubnet0'].OutputValue" \
  --output text)
export WOF_PUBLIC_SUBNET1=$(aws cloudformation describe-stacks  \
  --region $WOF_AWS_REGION \
  --stack-name $WOF_CFN_STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='PublicSubnet1'].OutputValue" \
  --output text)
export WOF_PRIVATE_SUBNET0=$(aws cloudformation describe-stacks  \
  --region $WOF_AWS_REGION \
  --stack-name $WOF_CFN_STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnet0'].OutputValue" \
  --output text)
export WOF_PRIVATE_SUBNET1=$(aws cloudformation describe-stacks  \
  --region $WOF_AWS_REGION \
  --stack-name $WOF_CFN_STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnet1'].OutputValue" \
  --output text)
export WOF_ALB_SG_ID=$(aws cloudformation describe-stacks  \
  --region $WOF_AWS_REGION \
  --stack-name $WOF_CFN_STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='ALBSecurityGroup'].OutputValue" \
  --output text)
export WOF_TG_ARN=$(aws cloudformation describe-stacks  \
  --region $WOF_AWS_REGION \
  --stack-name $WOF_CFN_STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='WordPressTargetGroup'].OutputValue" \
  --output text)


# SPOF - DB
# production - MULTI AZ
# aurora serverless


## https://hub.docker.com/r/bitnami/wordpress/dockerfile/


# task definition

cat > wp-task-definition.json << EOF
{   "networkMode": "awsvpc", 
    "containerDefinitions": [
        {
            
            "portMappings": [
                {
                    "containerPort": 8080,
                    "protocol": "tcp"
                }
            ],
            "essential": true,
            "mountPoints": [
                {
                    "containerPath": "/bitnami/wordpress",
                    "sourceVolume": "wordpress"
                }
            ],
            "name": "wordpress",
            "image": "bitnami/wordpress",
            "environment": [
                {
                    "name": "MARIADB_HOST",
                    "value": "${WOF_RDS_ENDPOINT}"
                },
                {   
                    "name": "WORDPRESS_DATABASE_USER",
                    "value": "admin"
                },
                {   
                    "name": "WORDPRESS_DATABASE_PASSWORD",
                    "value": "supersecretpassword"
                },
                {   
                    "name": "WORDPRESS_DATABASE_NAME",
                    "value": "wordpress"
                },
                {   
                    "name": "PHP_MEMORY_LIMIT",
                    "value": "512M"
                },
                {   
                    "name": "enabled",
                    "value": "false"
                },
                {   
                    "name": "ALLOW_EMPTY_PASSWORD",
                    "value": "yes"
                }
            ]
        }
    ],
    "requiresCompatibilities": [ 
        "FARGATE" 
    ],
    "cpu": "1024", 
    "memory": "3072", 
    "volumes": [
        {
            "name": "wordpress",
            "efsVolumeConfiguration": {
                "fileSystemId": "${WOF_EFS_FS_ID}",
                "transitEncryption": "ENABLED",
                "authorizationConfig": {
                    "accessPointId": "${WOF_EFS_AP}",
                    "iam": "DISABLED"
                }
            }
        }
    ],
    "family": "wof-tutorial"
}
EOF

WOF_TASK_DEFINITION_ARN=$(aws ecs register-task-definition \
--cli-input-json file://wp-task-definition.json \
--region $WOF_AWS_REGION \
--query taskDefinition.taskDefinitionArn --output text)

### ECS CLUSTER

aws ecs create-cluster \
  --cluster-name $WOF_ECS_CLUSTER_NAME \
  --region $WOF_AWS_REGION

WOF_SVC_SG_ID=$(aws ec2 create-security-group \
  --description Svc-WordPress-on-Fargate \
  --group-name Svc-WordPress-on-Fargate \
  --vpc-id $WOF_VPC_ID --region $WOF_AWS_REGION \
  --query 'GroupId' --output text)

##Accept traffic on port 8080
aws ec2 authorize-security-group-ingress \
  --group-id $WOF_SVC_SG_ID --protocol tcp \
  --port 8080 --source-group $WOF_ALB_SG_ID \
  --region $WOF_AWS_REGION

aws ecs create-service \
  --cluster $WOF_ECS_CLUSTER_NAME \
  --service-name wof-efs-rw-service \
  --task-definition "${WOF_TASK_DEFINITION_ARN}" \
  --load-balancers targetGroupArn="${WOF_TG_ARN}",containerName=wordpress,containerPort=8080 \
  --desired-count 2 \
  --platform-version 1.4.0 \
  --launch-type FARGATE \
  --deployment-configuration maximumPercent=100,minimumHealthyPercent=0 \
  --network-configuration "awsvpcConfiguration={subnets=["$WOF_PRIVATE_SUBNET0,$WOF_PRIVATE_SUBNET1"],securityGroups=["$WOF_SVC_SG_ID"],assignPublicIp=DISABLED}"\
  --region $WOF_AWS_REGION
  
#Wait until there two running tasks
watch aws ecs describe-services \
  --services wof-efs-rw-service \
  --cluster $WOF_ECS_CLUSTER_NAME \
  --region $WOF_AWS_REGION \
  --query 'services[].runningCount' 
  
