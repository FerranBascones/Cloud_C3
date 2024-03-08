aws ecs update-service \
  --cluster $WOF_ECS_CLUSTER_NAME \
  --region $WOF_AWS_REGION \
  --service wof-efs-rw-service \
  --task-definition "$WOF_TASK_DEFINITION_ARN" \
  --desired-count 0 
  
sleep 3

aws ecs update-service \
  --cluster $WOF_ECS_CLUSTER_NAME \
  --region $WOF_AWS_REGION \
  --service wof-efs-rw-service \
  --task-definition "$WOF_TASK_DEFINITION_ARN" \
  --desired-count 2
  
# autoescalat
aws application-autoscaling \
  register-scalable-target \
  --region $WOF_AWS_REGION \
  --service-namespace ecs \
  --resource-id service/${WOF_ECS_CLUSTER_NAME}/wof-efs-rw-service \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 2 \
  --max-capacity 4


# política d'autoescalat
cat > scaling.config.json << EOF
{
     "TargetValue": 75.0,
     "PredefinedMetricSpecification": {
         "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
     },
     "ScaleOutCooldown": 60,
    "ScaleInCooldown": 60
}
EOF

aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id service/${WOF_ECS_CLUSTER_NAME}/wof-efs-rw-service \
  --policy-name cpu75-target-tracking-scaling-policy \
  --policy-type TargetTrackingScaling \
  --region $WOF_AWS_REGION \
  --target-tracking-scaling-policy-configuration file://scaling.config.json

wget https://hey-release.s3.us-east-2.amazonaws.com/hey_linux_amd64

#### ./hey_linux_amd64 -z 20m  <WordPress URL>

chmod a+rx  hey_linux_amd64

