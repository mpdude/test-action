#!/bin/bash -e

export DEPLOYMENT_DIR=$(dirname $(readlink -f $0))/..

function BeforeInstall() {
    export AWS_DEFAULT_REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region`
    read -r REPO_URL COMMIT_ID <<< $(aws deploy get-deployment --deployment-id=$DEPLOYMENT_ID | jq -r '"git@github.com:\(.deploymentInfo.revision.gitHubLocation.repository).git " + .deploymentInfo.revision.gitHubLocation.commitId')
    export REPO_URL COMMIT_ID

    export RELEASE=`date +%Y%m%d%H%M%S`
    echo $RELEASE > $DEPLOYMENT_DIR/depp-release-version

    eval `ssh-agent -s`
    trap "echo Killing SSH agent with PID $SSH_AGENT_PID; kill $SSH_AGENT_PID" 0
    ssh-add

    cd /var/www

    if [ -d $DEPLOYMENT_GROUP_NAME ]; then
        echo updating deployment TBD
    else
        depp setup "$DEPLOYMENT_GROUP_NAME" "$REPO_URL" "$COMMIT_ID"
    fi

}

function ApplicationStart() {
    cd /var/www/$DEPLOYMENT_GROUP_NAME
    [ -L current_version ] && basename $(readlink -f current_version) > $DEPLOYMENT_DIR/depp-previous-release
    depp deploy $(cat $DEPLOYMENT_DIR/depp-release-version)
}

function ValidateService() {
  true
}

case $LIFECYCLE_EVENT in

    BeforeInstall)
        BeforeInstall
    ;;

    AfterInstall)
    ;;

    ApplicationStart)
        ApplicationStart
    ;;

    ValidateService)
        ValidateService
    ;;

esac
