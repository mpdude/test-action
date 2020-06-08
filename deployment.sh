#!/bin/bash -e

export DEPLOYMENT_DIR=$(dirname $(readlink -f $0))/..

function ApplicationStop() {
    CURRENT_DEPLOYMENT=/var/www/$DEPLOYMENT_GROUP_NAME/current_version
    if [ -d $CURRENT_DEPLOYMENT ]; then
        cd $CURRENT_DEPLOYMENT
        [ ! -f meta/wfdynamic.xml ] || (echo "Dumpe aktuelle wfDynamic-Konfiguration" && phlough wfdynamic:configuration-dump)
        git diff-files --exit-code || (echo Es gibt untracked files und/oder uncommitted changes in `pwd`. Breche ab.; exit 1)
    else
        echo "Es gibt keine laufende Version in $CURRENT_DEPLOYMENT; führe keine weiteren Tests aus."
    fi
}

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

function ApplicationStart() {
    cd /var/www/$DEPLOYMENT_GROUP_NAME
    depp deploy $DEPLOYMENT_ID

    for EXISTING_DEPLOYMENT in `ls -d d-????????? 2>/dev/null`; do
        [ -d $DEPLOYMENT_DIR/../$EXISTING_DEPLOYMENT ] || echo "$DEPLOYMENT_DIR/../$EXISTING_DEPLOYMENT existiert nicht, also kann $EXISTING_DEPLOYMENT wahrscheinlich weg"
    done
    #for TMP in `ls -d tmp/symfony-* 2>/dev/null`; do F=`echo $TMP | sed 's/tmp\/symfony-//'`; test -d $F || sudo rm -rf $TMP ; done
    for TMP in `ls -d tmp/symfony-* 2>/dev/null`; do
        F=`echo $TMP | sed 's/tmp\/symfony-//'`
        test -d $F || echo $TMP kann wahrscheinlich weg
    done
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
