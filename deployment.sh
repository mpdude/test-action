#!/bin/bash -ex

export DEPLOYMENT_DIR=$(dirname $(readlink -f $0))/..

function BeforeInstall() {
    export AWS_DEFAULT_REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region`
    read -r REPO_URL COMMIT_ID <<< $(aws deploy get-deployment --deployment-id=$DEPLOYMENT_ID | jq -r '"git@github.com:\(.deploymentInfo.revision.gitHubLocation.repository).git " + .deploymentInfo.revision.gitHubLocation.commitId')
    export REPO_URL COMMIT_ID
    export RELEASE=$DEPLOYMENT_ID

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
    STOPPING_DEPLOYMENT_ID=$(basename $(readlink -f $DEPLOYMENT_DIR))
    OLD_DEPLOYMENT_DIR=/var/www/$DEPLOYMENT_GROUP_NAME/$STOPPING_DEPLOYMENT_ID
    if [ -d $OLD_DEPLOYMENT_DIR ]; then
        cd $OLD_DEPLOYMENT_DIR
        [ -f meta/wfdynamic.xml ] && echo "Dumpe aktuelle wfDynamic-Konfiguration" && phlough wfdynamic:configuration-dump
        git diff-index --quiet HEAD -- || (echo Es gibt untracked files und/oder uncommitted changes in `pwd`. Breche ab.; exit 1)
    else
        echo "Das alte Deployment-Verzeichnis $OLD_DEPLOYMENT_DIR existiert nicht mehr; führe keine weiteren Tests aus."
    fi
}

function ApplicationStart() {
    cd /var/www/$DEPLOYMENT_GROUP_NAME
    depp deploy $DEPLOYMENT_ID
}

function AfterInstall() {
    cd /var/www/$DEPLOYMENT_GROUP_NAME/$DEPLOYMENT_ID
    if [ -x bin/console ]; then
        if bin/console list --raw | grep -q doctrine:migrations:migrate; then
            bin/console doctrine:migrations:migrate --allow-no-migration --no-ansi --no-interaction
        fi
    fi
    if [ -f meta/wfdynamic.xml ]; then
        phlough wfdynamic:configuration-import
    fi
}

case $LIFECYCLE_EVENT in
    ApplicationStop)
        ApplicationStop
    ;;

    BeforeInstall)
        BeforeInstall
    ;;

    AfterInstall)
        AfterInstall
    ;;

    ApplicationStart)
        ApplicationStart
    ;;
esac
