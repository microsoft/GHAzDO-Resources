import * as path from 'path';
import * as task from 'azure-pipelines-task-lib/task';
import * as telemetry from 'azure-pipelines-tasks-utility-common/telemetry'
import { getPlatform } from './taskutil';
import { useCodeQLVersion } from './usecodeqlversion';

(async () => {
    try {
        task.setResourcePath(path.join(__dirname, 'task.json'));
        const versionSpec = task.getInput('versionSpec', true);
        const disableDownloadFromRegistry = task.getBoolInput('disableDownloadFromRegistry');
        const allowUnstable = task.getBoolInput('allowUnstable');
        const addToPath = task.getBoolInput('addToPath', true);
        const githubToken = task.getInput('githubToken', false);
        await useCodeQLVersion({
            versionSpec,
            allowUnstable,
            disableDownloadFromRegistry,
            addToPath,
            githubToken
        },
        getPlatform());
        task.setResult(task.TaskResult.Succeeded, "");
        telemetry.emitTelemetry('TaskHub', 'UseCodeQLVersionV0', {
            versionSpec,
            addToPath
        });
    } catch (error) {
        task.setResult(task.TaskResult.Failed, error.message);
    }
})();
