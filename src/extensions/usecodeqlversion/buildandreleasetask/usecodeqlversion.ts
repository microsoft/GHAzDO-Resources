import * as os from 'os';
import * as task from 'azure-pipelines-task-lib/task';
import * as tool from 'azure-pipelines-tool-lib/tool';
import { installCodeQLVersion } from './installcodeqlversion';
import * as toolUtil  from './toolutil';
import { codeQLVersionToSemantic, isExactVersion } from './versionspec';
import { Platform } from './taskutil';
import { TaskParameters } from './interfaces';


export async function useCodeQLVersion(parameters: Readonly<TaskParameters>, platform: Platform): Promise<void> {
    const semanticVersionSpec = await codeQLVersionToSemantic(parameters);
    task.debug(`Semantic version spec of ${parameters.versionSpec} is ${semanticVersionSpec}`);

    if (isExactVersion(semanticVersionSpec)) {
        task.warning(task.loc('ExactVersionNotRecommended'));
    }

    let installDir: string | null = tool.findLocalTool('CodeQL', semanticVersionSpec);
    // CodeQL version not found in local cache, try to download and install
    
    if (!installDir) {
        task.debug(`Could not find a local CodeQL installation matching ${semanticVersionSpec}.`);
        if (!parameters.disableDownloadFromRegistry) {
            try {
                task.debug('Trying to download CodeQL from registry.');
                await installCodeQLVersion(semanticVersionSpec, parameters);
                installDir = tool.findLocalTool('CodeQL', semanticVersionSpec);
                if (installDir) {
                    task.debug(`Successfully installed CodeQL from registry to ${installDir}.`);
                }
            } catch (err) {
                task.error(task.loc('DownloadFailed', err.toString()));
            }
        }
    }

    // If still not found, then both local check and download have failed
    if (!installDir) {
        // Fail and list available versions
        const Versions = tool.findLocalToolVersions('CodeQL')
            .map(s => `${s}`)
            .join(os.EOL);

        throw new Error([
            task.loc('VersionNotFound', parameters.versionSpec),
            task.loc('ListAvailableVersions', task.getVariable('Agent.ToolsDirectory')),
            Versions,
            task.loc('ToolNotFoundMicrosoftHosted', 'CodeQL', 'https://aka.ms/hosted-agent-software'),
            task.loc('ToolNotFoundSelfHosted', 'CodeQL', 'https://github.com/github/codeql-action/releases')
        ].join(os.EOL));
    }

    task.setVariable('CodeQLLocation', installDir);
    if (parameters.addToPath) {
        toolUtil.prependPathSafe(installDir);
    }
}