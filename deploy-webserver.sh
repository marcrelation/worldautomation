#!/bin/bash

# USAGE : ./deploy-webserver.sh <profile> <aws-region> <build-type(Simple or HA) <project-name> <instance-type> <VPC CIDR> <subnet1 CIDR> <subnet2 CIDR>
#		  ./deploy-webserver.sh default us-east-1 HA "10.192.0.0/16" "10.192.10.0/24" "10.192.11.0/24"
# PRE-REQUISITES
# bash installed in your path
# aws cli installed in your path
# curl installed in your path
# ~/.aws/credentials file setup with at least one profile.  If that profile is not named default you will need to provide it on the command line.

PROFILE=$1
REGION=$2
TYPE=$3
PROJECT_NAME=$4
INSTANCE_TYPE=$5
VPC_CIDR=$6
SUBNET1_CIDR=$7
SUBNET2_CIDR=$8

TEMPLATE_DIR="$( cd "$(dirname "$0")" ; pwd -P )"


if [[ -z $PROFILE ]]; then
       PROFILE="default"
fi
if [[ -z $REGION ]]; then
       REGION="us-east-1"
fi
if [[ -z $TYPE ]]; then
       TYPE="Simple"
fi
if [[ -z $PROJECT_NAME ]]; then
       PROJECT_NAME="worldautomation"
fi
if [[ -z $INSTANCE_TYPE ]]; then
       INSTANCE_TYPE="t1.micro"
fi
if [[ -z $VPC_CIDR ]]; then
       VPC_CIDR="10.192.0.0/16"
fi
if [[ -z $SUBNET1_CIDR ]]; then
       SUBNET1_CIDR="10.192.10.0/24"
fi
if [[ -z $SUBNET2_CIDR ]]; then
       SUBNET2_CIDR="10.192.11.0/24"
fi

# SHOULDNT NEED TO CONFIGURE THIS.
STACK_NAME="$PROJECT_NAME-$TYPE"

# RUN VPC / DATABASE CLOUDFORMATION
if [[ "Simple" == $TYPE ]]; then
    OUTPUT_SEARCH_STR="WebServerIpAddress"
    echo aws --profile=$PROFILE --region=$REGION cloudformation --capabilities=CAPABILITY_NAMED_IAM create-stack --stack-name "$STACK_NAME" \
        --template-body file://$TEMPLATE_DIR/$TYPE-WebServer.yaml \
	    --parameters ParameterKey=ProjectName,ParameterValue="$PROJECT_NAME" \
		    ParameterKey=WebServerInstanceType,ParameterValue="$INSTANCE_TYPE" \
		    ParameterKey=PublicSubnet1CIDR,ParameterValue="$SUBNET1_CIDR" \
		    ParameterKey=VpcCIDR,ParameterValue="$VPC_CIDR"

    aws --profile=$PROFILE --region=$REGION cloudformation --capabilities=CAPABILITY_NAMED_IAM create-stack --stack-name "$STACK_NAME" \
        --template-body file://$TEMPLATE_DIR/$TYPE-WebServer.yaml \
	    --parameters ParameterKey=ProjectName,ParameterValue="$PROJECT_NAME" \
		    ParameterKey=WebServerInstanceType,ParameterValue="$INSTANCE_TYPE" \
		    ParameterKey=PublicSubnet1CIDR,ParameterValue="$SUBNET1_CIDR" \
		    ParameterKey=VpcCIDR,ParameterValue="$VPC_CIDR"
else
    OUTPUT_SEARCH_STR="LoadBalancerAddress"
    echo aws --profile=$PROFILE --region=$REGION cloudformation --capabilities=CAPABILITY_NAMED_IAM create-stack --stack-name "$STACK_NAME" \
        --template-body file://$TEMPLATE_DIR/$TYPE-WebServer.yaml \
	    --parameters ParameterKey=ProjectName,ParameterValue="$PROJECT_NAME" \
		    ParameterKey=WebServerInstanceType,ParameterValue="$INSTANCE_TYPE" \
		    ParameterKey=PublicSubnet1CIDR,ParameterValue="$SUBNET1_CIDR" \
		    ParameterKey=PublicSubnet2CIDR,ParameterValue="$SUBNET2_CIDR" \
		    ParameterKey=VpcCIDR,ParameterValue="$VPC_CIDR"

    aws --profile=$PROFILE --region=$REGION cloudformation --capabilities=CAPABILITY_NAMED_IAM create-stack --stack-name "$STACK_NAME" \
        --template-body file://$TEMPLATE_DIR/$TYPE-WebServer.yaml \
	    --parameters ParameterKey=ProjectName,ParameterValue="$PROJECT_NAME" \
		    ParameterKey=WebServerInstanceType,ParameterValue="$INSTANCE_TYPE" \
		    ParameterKey=PublicSubnet1CIDR,ParameterValue="$SUBNET1_CIDR" \
		    ParameterKey=PublicSubnet2CIDR,ParameterValue="$SUBNET2_CIDR" \
		    ParameterKey=VpcCIDR,ParameterValue="$VPC_CIDR"
fi
	
# WAIT UNTIL THE STACK IS CREATE_COMPLETE AND THEN CONTINUE
# WAIT 5 MINUTES BETWEEN CHECKS
STACK_STATUS=""
while [[ -z $STACK_STATUS  || $STACK_STATUS != "CREATE_COMPLETE" ]]
do
STACK_STATUS=`aws --profile=$PROFILE --region=$REGION cloudformation describe-stacks --stack-name=$STACK_NAME --query="Stacks[0].StackStatus" --output=text`

if [[ $STACK_STATUS == "ROLLBACK_IN_PROGRESS" || $STACK_STATUS == "ROLLBACK_COMPLETE" || $STACK_STATUS == "CREATE_FAILED" ]]; then
	echo "Cloudformation failed."
	exit -1;
fi

if [[ -z $STACK_STATUS || $STACK_STATUS != "CREATE_COMPLETE" ]]; then
        echo `date` "-> StackStatus is currently $STACK_STATUS... sleeping for 5 minutes..."
        sleep 300
fi
done
echo "Stack status completed: $STACK_STATUS"

# NOW GET THE IP FOR THE WEBSERVER
WEBSERVER=$(aws --profile=$PROFILE --region=$REGION cloudformation describe-stacks --stack-name=$STACK_NAME | grep --context=2 $OUTPUT_SEARCH_STR | grep OutputValue | cut -d: -f2 | sed -e 's/"//g' -e 's/ //g')

# NOW CHECK TO SEE IF WE CAN GET THE STRING FROM THE WEBSERVER
# LETS DO THIS IN A LOOP AND WAIT A FEW MINUTES BECAUSE IT COULD JUST TAKE TIME...
COUNT=0
RETRIES=10
while : ; do
    if [[ $COUNT -lt $RETRIES ]]; then
        RESULTS=$(curl -sk -m 5 http://$WEBSERVER | grep "Automation for the people")
        if [[ -z $RESULTS ]]; then
            let COUNT=COUNT+1
            echo "Server $WEBSERVER is not up yet... lets wait another 30 seconds..."
            sleep 30
        else
            echo "Server $WEBSERVER is up and running successfully at http://$WEBSERVER and there was much rejoincing"
            break
        fi
    else
        echo "Server never came up successfully and there was much crying"
        break
    fi
done
