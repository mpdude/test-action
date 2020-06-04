#!/bin/sh -ex

export AWS_DEFAULT_REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region`
read -r REPOSITORY_NAME COMMIT_ID <<< $(aws deploy get-deployment --deployment-id=$DEPLOYMENT_ID | jq -r '.deploymentInfo.revision.gitHubLocation.repository + " " + .deploymentInfo.revision.gitHubLocation.commitId')
export REPOSITORY_NAME COMMIT_ID 
who am i
pwd
printenv
