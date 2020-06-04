#!/bin/sh -ex

who am i
pwd
printenv

aws deploy get-deployment --deployment-id=$DEPLOYMENT_ID | jq .
