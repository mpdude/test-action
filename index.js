const core = require('@actions/core');
const fs = require('fs');
const yaml = require('js-yaml');

const github = require('@actions/github');
const payload = github.context.payload;

function fetchBranchConfig(branchName) {
    let fileContents = fs.readFileSync('./appspec.yml', 'utf8');
    let data = yaml.safeLoad(fileContents);

    for (var prop in data.branch_config) {
        var regex = new RegExp('^' + prop + '$', 'i');
        if (branchName.match(regex)) {
            console.log(`💡 Using branch_config '${prop}' for branch '${branchName}'`);
            return data.branch_config[prop];
        }
    }

    core.setFailed('❓ Found no matching deployment_group_config – aborting');
    process.exit();
}

(async function () {
    var deploymentId;

    const applicationName = core.getInput('application') || payload.repository.name;
    const fullRepositoryName = payload.repository.full_name;

    const isPullRequest = payload.pull_request !== undefined;
    const commitId = isPullRequest ? payload.pull_request.head.sha : payload.head_commit.id;
    const branchName = isPullRequest ? payload.pull_request.head.ref : payload.ref.replace(/^refs\/heads\//, '');
    console.log(`On branch '${branchName}', head commit ${commitId}`);

    const branchConfig = fetchBranchConfig(branchName);
    const safeBranchName = branchName.replace(/[^a-z0-9-/]+/gi, '-').replace(/\/+/, '--');
    const deploymentGroupName = branchConfig.deploymentGroupName ? branchConfig.deploymentGroupName.replace('$BRANCH', safeBranchName) : safeBranchName;
    const deploymentGroupConfig = branchConfig.deploymentGroupConfig;

    console.log(`Using '${deploymentGroupName}' as deployment group name`);

    const client = require('aws-sdk/clients/codedeploy');
    const codeDeploy = new client();

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
            await codeDeploy.createDeploymentGroup({
                ...deploymentGroupConfig,
                ...{
                    applicationName: applicationName,
                    deploymentGroupName: deploymentGroupName,
                }
            }).promise();
            console.log(`🎯 Created a new deployment group ${deploymentGroupName}`);
        } else {
            throw e;
        }
    }

    let tries = 0;
    while (true) {

        if (++tries > 5) {
            core.setFailed('🤥 Unable to create a deployment, possibly due too much concurrency');
            return;
        }

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
                        repository: fullRepositoryName
                    }
                }
            }).promise();
            console.log(`🚚️ Created deployment ${deploymentId} – https://console.aws.amazon.com/codesuite/codedeploy/deployments/${deploymentId}`);
            core.setOutput('deploymentId', deploymentId);
            break;
        } catch (e) {
            if (e.code == 'DeploymentLimitExceededException') {
                var [, otherDeployment] = e.message.toString().match(/is already deploying deployment \'(d-\w+)\'/);
                console.log(`😶 Waiting for another pending deployment ${otherDeployment}`);
                try {
                    await codeDeploy.waitFor('deploymentSuccessful', {deploymentId: otherDeployment}).promise();
                    console.log(`🙂 The pending deployment ${otherDeployment} sucessfully finished.`);
                } catch (e) {
                    console.log(`🤔 The other pending deployment ${otherDeployment} seems to have failed.`);
                }
                continue;
            } else {
                throw e;
            }
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
