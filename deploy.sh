#!/bin/bash

# Exit on error
set -e

# Check the args
if [ "$#" -ne 2 ]; then
    echo -e "Error: exactly two parameters are required\n"

    echo "Usage: ${0} STACK_NAME APPROVAL_ARNS"
    echo "  STACK_NAME - What you want to call the CloudFormation stack this script will create"
    echo "  IAM_ARNS - A comma-delimited list of IAM ARNs who will be allowed to approve VPC endpoint connection requests"

    IAM_USER_ARN=`aws iam get-user --query "User.Arn" | tr -d [\"]`
    echo "             Helpful hint, your IAM user ARN is ${IAM_USER_ARN}"

    exit 1
fi

STACK_MAIN=${1}
STACK_ADDON=${STACK_MAIN}-addon
IAM_ARNS=${2}

echo "Creating stack ${STACK_MAIN}"
aws cloudformation create-stack --stack-name ${STACK_MAIN} --template-body file://main-stack.yaml --parameters ParameterKey=VpcEndpointConnectionApprovers,ParameterValue=${IAM_ARNS}

echo "Spawning background process to poll and accept VPC endpoint requests while ${STACK_MAIN} is created"
exec ./poll-and-accept-endpoint-requests.sh ${STACK_MAIN} &
aws cloudformation wait stack-create-complete --stack-name ${STACK_MAIN}
echo "Stack ${STACK_MAIN} created"

echo "Gathering information from ${STACK_MAIN} that is needed for ${STACK_ADDON}"
REDSHIFT_CLUSTER_ID=`aws cloudformation describe-stack-resource --stack-name ${STACK_MAIN} --logical-resource-id bRedshiftCluster --query "StackResourceDetail.PhysicalResourceId" | tr -d [\"]`
echo "Found Redshift cluster ${REDSHIFT_CLUSTER_ID}"
REDSHIFT_PRIVATE_IP=`aws redshift describe-clusters --cluster-identifier ${REDSHIFT_CLUSTER_ID} --query "Clusters[0].ClusterNodes[0].PrivateIPAddress" | tr -d [\"]`
echo "Will use private IP ${REDSHIFT_PRIVATE_IP} for the NLB's target in the addon stack"

echo "Creating stack ${STACK_ADDON}"
aws cloudformation create-stack --stack-name ${STACK_ADDON} --template-body file://vpc-endpoint-addon.yaml --parameters ParameterKey=MainStackName,ParameterValue=${STACK_MAIN} ParameterKey=RedshiftPrivateIP,ParameterValue=${REDSHIFT_PRIVATE_IP}


aws cloudformation wait stack-create-complete --stack-name ${STACK_ADDON}
echo "Stack ${STACK_ADDON} created"

echo "Done!"
