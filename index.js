const core = require('@actions/core');
const fs = require('fs');
const yaml = require('js-yaml');

const github = require('@actions/github');

const payload = JSON.stringify(github.context.payload, undefined, 2);
console.log(`The event payload: ${payload}`);

function fetchDeploymentGroupConfig(branchName) {
    let fileContents = fs.readFileSync('./appspec.yml', 'utf8');
    let data = yaml.safeLoad(fileContents);

    for (var prop in data.deployment_group_config) {
        var regex = new RegExp('^' + prop + '$', 'i');
        if (branchName.match(regex)) {
            console.log(`💡 Using deployment_group_config key '${prop}' for branch '${branchName}'`);
            return data.deployment_group_config[prop];
        }
    }

    core.setFailed('❓ Found no matching deployment_group_config – aborting');
    process.exit();
}

(async function () {
    var deploymentId;

    const applicationName = core.getInput('application-name');
    const region = core.getInput('aws-region');

    const branchName = 'test-branch'; // aus Kontext
    const repositoryName = 'webfactory/baton-test-repo'; // aus Kontext
    const commitId = '38997b7bb0bd3eb2ace0a8c614a76c14b8b3f0dd'; // aus Kontext

    const deploymentGroupName = branchName; // ableiten

    const client = require('aws-sdk/clients/codedeploy');
    const codeDeploy = new client({region: region});

    const deploymentGroupConfig = fetchDeploymentGroupConfig('test-branch');

    try {
        await codeDeploy.updateDeploymentGroup({
            ...deploymentGroupConfig,
            ...{
                applicationName: applicationName,
                currentDeploymentGroupName: deploymentGroupName
            }
        }).promise();
        console.log(`⚙️  Updated deployment group ${deploymentGroupName}`);
    } catch (e) {
        if (e.code == 'DeploymentGroupDoesNotExistException') {
            await codeDeploy.createDeploymentGroup(
                ...deploymentGroupConfig,
                ...{
                    applicationName: applicationName,
                    deploymentGroupName: deploymentGroupName,
                }
            ).promise();
            console.log(`🎯 Created a new deployment group ${deploymentGroupName}`);
        } else {
            throw e;
        }
    }

    for (let tries = 0; tries < 5; tries++) {
        try {
            var {deploymentId: deploymentId} = await codeDeploy.createDeployment({
                applicationName: applicationName,
                autoRollbackConfiguration: {
                    enabled: true,
                    events: ['DEPLOYMENT_FAILURE', 'DEPLOYMENT_STOP_ON_ALARM', 'DEPLOYMENT_STOP_ON_REQUEST'],
                },
                deploymentGroupName: deploymentGroupName,
                revision: {
                    revisionType: 'GitHub',
                    gitHubLocation: {
                        commitId: commitId,
                        repository: repositoryName
                    }
                }
            }).promise();
            console.log(`🚚️ Created deployment ${deploymentId} – https://${region}.console.aws.amazon.com/codesuite/codedeploy/deployments/${deploymentId}`);
            core.setOutput("deploymentId", deploymentId);
            break;
        } catch (e) {
            if (e.code == 'DeploymentLimitExceededException') {
                var [, otherDeployment] = e.message.toString().match(/is already deploying deployment \'(d-\w+)\'/);
                console.log(`😶 Waiting for another pending deployment ${otherDeployment}`);
            }
            try {
                await codeDeploy.waitFor('deploymentSuccessful', {deploymentId: otherDeployment}).promise();
                console.log(`🙂 The pending deployment ${otherDeployment} sucessfully finished.`);
            } catch (e) {
                console.log(`🤔 The other pending deployment ${otherDeployment} seems to have failed.`);
            }
            continue;
        }
    }

    console.log(`⏲  Waiting for deployment ${deploymentId} to finish`);

    try {
        await codeDeploy.waitFor('deploymentSuccessful', {deploymentId: deploymentId}).promise();
        console.log('🥳 Deployment successful');
    } catch (e) {
        core.setFailed(`😱 The deployment ${deploymentId} seems to have failed.`);
    }
})();
