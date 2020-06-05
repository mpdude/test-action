#!/bin/bash -ex

export AWS_DEFAULT_REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region`
read -r REPO_URL COMMIT_ID <<< $(aws deploy get-deployment --deployment-id=$DEPLOYMENT_ID | jq -r '"git@github.com:\(.deploymentInfo.revision.gitHubLocation.repository).git " + .deploymentInfo.revision.gitHubLocation.commitId')
export REPO_URL COMMIT_ID

cd /var/www
if [ -d $DEPLOYMENT_GROUP ]; then
    echo updating deployment TBD
else
    depp setup "$DEPLOYMENT_GROUP" "$REPO_URL" "$COMMIT_ID"
fi 
