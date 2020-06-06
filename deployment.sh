#!/bin/bash -e

export DEPLOYMENT_DIR=$(dirname $(readlink -f $0))/..

function BeforeInstall() {
    export AWS_DEFAULT_REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region`
    read -r REPO_URL COMMIT_ID <<< $(aws deploy get-deployment --deployment-id=$DEPLOYMENT_ID | jq -r '"git@github.com:\(.deploymentInfo.revision.gitHubLocation.repository).git " + .deploymentInfo.revision.gitHubLocation.commitId')
    export REPO_URL COMMIT_ID

    # export RELEASE=`date +%Y%m%d%H%M%S`
    export RELEASE=$DEPLOYMENT_ID
    #echo $RELEASE > $DEPLOYMENT_DIR/depp-release-version

    eval `ssh-agent -s`
    trap "echo Killing SSH agent with PID $SSH_AGENT_PID; kill $SSH_AGENT_PID" 0
    ssh-add

    cd /var/www

    if [ -d $DEPLOYMENT_GROUP_NAME ]; then
        echo Release sollte $RELEASE werden, commit $COMMIT_ID
        cd $DEPLOYMENT_GROUP_NAME
        REF=$COMMIT_ID depp prepare
    else
        depp setup "$DEPLOYMENT_GROUP_NAME" "$REPO_URL" "$COMMIT_ID"
    fi

}

function ApplicationStop() {
    cd /var/www/$DEPLOYMENT_GROUP_NAME/$DEPLOYMENT_ID
    [ -f meta/wfdynamic.xml ] && phlough wfdynamic:configuration-dump
    git diff-index --quiet HEAD -- || (echo Es gibt untracked files und/oder uncommitted changes in `pwd`. Breche ab.; exit 1)
}

function ApplicationStart() {
    cd /var/www/$DEPLOYMENT_GROUP_NAME
    # [ -L current_version ] && basename $(readlink -f current_version) > $DEPLOYMENT_DIR/depp-previous-release
    #depp deploy $(cat $DEPLOYMENT_DIR/depp-release-version)
    depp deploy $DEPLOYMENT_ID
}

function ValidateService() {
  true
}

case $LIFECYCLE_EVENT in

    ApplicationStop)
        ApplicationStop
    ;;

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
