#!/bin/bash -ex

export AWS_DEFAULT_REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region`
read -r REPO_URL COMMIT_ID <<< $(aws deploy get-deployment --deployment-id=$DEPLOYMENT_ID | jq -r '"git@github.com:\(.deploymentInfo.revision.gitHubLocation.repository).git " + .deploymentInfo.revision.gitHubLocation.commitId')
export REPO_URL COMMIT_ID
export RELEASE=`date +%Y%m%d%H%M%S`

eval `ssh-agent -s`
trap "echo Killing SSH agent with PID $SSH_AGENT_PID; kill $SSH_AGENT_PID" 0

printenv
ssh-add

cd /var/www
if [ -d $DEPLOYMENT_GROUP_NAME ]; then
    echo updating deployment TBD
else
    git clone "git@github.com:webfactory/symfony-webfactory-edition.git" "$DEPLOYMENT_GROUP_NAME"
    # depp setup "$DEPLOYMENT_GROUP" "$REPO_URL" "$COMMIT_ID"
fi 
