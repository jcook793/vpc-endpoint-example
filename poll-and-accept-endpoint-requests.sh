#!/bin/bash

POLL_INTERVAL_SECONDS=5
MAX_POLLING_ATTEMPTS=360
STACK_NAME=${1}

SERVICE_ID=null
VPC_ENDPOINT_ID=null
POLL_COUNT=0


function get_service_id {
    if [ "null" = "${SERVICE_ID}" ]; then
        echo -n "Looking for bVPCEndPointService in stack ${STACK_NAME}..."
        SERVICE_ID=`aws cloudformation describe-stack-resource --stack-name ${STACK_NAME} --logical-resource-id bVPCEndPointService --query "StackResourceDetail.PhysicalResourceId" 2> /dev/null | tr -d [\"]`
        exit_status=$?
        if [ ${exit_status} -ne 0 ] || [ "" = "${SERVICE_ID}" ]; then
            echo " not yet created"
            SERVICE_ID=null
        else
            echo " ${SERVICE_ID}"
        fi
    fi
}

function get_vpc_endpoint_id {
    if [ "null" = "${VPC_ENDPOINT_ID}" ]; then
        echo -n "Looking for aVPCEndpoint in stack ${STACK_NAME}..."
        VPC_ENDPOINT_ID=`aws cloudformation describe-stack-resource --stack-name ${STACK_NAME} --logical-resource-id aVPCEndpoint --query "StackResourceDetail.PhysicalResourceId" 2> /dev/null | tr -d [\"]`
        exit_status=$?
        if [ ${exit_status} -ne 0 ] || [ "" = "${VPC_ENDPOINT_ID}" ]; then
            echo " not yet created"
            VPC_ENDPOINT_ID=null
        else
            echo " ${VPC_ENDPOINT_ID}"
        fi
    fi    
}


while true; do
    get_service_id
    get_vpc_endpoint_id

    if [ "null" != "${SERVICE_ID}" ] && [ "null" != "${VPC_ENDPOINT_ID}" ]; then
        if [ ${POLL_COUNT} -eq 0 ]; then
            MINUTES=`echo "${MAX_POLLING_ATTEMPTS} * ${POLL_INTERVAL_SECONDS} / 60" | bc`
            echo -n "Polling for pending requests every ${POLL_INTERVAL_SECONDS} seconds up to ${MAX_POLLING_ATTEMPTS} times (~${MINUTES} minutes max)... "
        fi

        ID_RETURNED=`aws ec2 describe-vpc-endpoint-connections --filters Name=service-id,Values=${SERVICE_ID} Name=vpc-endpoint-id,Values=${VPC_ENDPOINT_ID} Name=vpc-endpoint-state,Values=pendingAcceptance --query "VpcEndpointConnections[0].VpcEndpointId" | tr -d [\"]`
        ((POLL_COUNT++))
        if [ "${ID_RETURNED}" = "${VPC_ENDPOINT_ID}" ]; then
            echo "Found a pending request! Issuing acceptance... "
            aws ec2 accept-vpc-endpoint-connections --service-id ${SERVICE_ID} --vpc-endpoint-ids ${VPC_ENDPOINT_ID}
            echo "done"
            exit 0
        else
            echo -n "${POLL_COUNT} "
        fi
    fi

    if [ ${POLL_COUNT} -ge ${MAX_POLLING_ATTEMPTS} ]; then
        echo -e "\nNo pending requests found after ${POLL_COUNT} attempts, giving up"
        exit 1
    fi

    sleep ${POLL_INTERVAL_SECONDS}
done
