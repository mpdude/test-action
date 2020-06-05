#!/bin/bash -ex

export AWS_DEFAULT_REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region`
read -r REPO_URL COMMIT_ID <<< $(aws deploy get-deployment --deployment-id=$DEPLOYMENT_ID | jq -r '"git@github.com:\(.deploymentInfo.revision.gitHubLocation.repository).git " + .deploymentInfo.revision.gitHubLocation.commitId')
export REPO_URL COMMIT_ID
export RELEASE=`date +%Y%m%d%H%M%S`

eval `$SSHAGENT $SSHAGENTARGS`
printenv

trap "echo 'Killing SSH agent.'; kill $SSH_AGENT_PID" 0

echo SSH Agent PID $SSH_AGENT_PID

cd /var/www
if [ -d $DEPLOYMENT_GROUP_NAME ]; then
    echo updating deployment TBD
else
    git clone "$REPO_URL" "$DEPLOYMENT_GROUP_NAME"
    # depp setup "$DEPLOYMENT_GROUP" "$REPO_URL" "$COMMIT_ID"
fi 
