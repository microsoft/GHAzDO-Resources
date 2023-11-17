import * as task from 'azure-pipelines-task-lib/task';
import * as rest from 'typed-rest-client';
import { TaskParameters, CodeQLRelease } from './interfaces';
const LATEST_URL = 'https://api.github.com/repos/github/codeql-action/releases/latest';

export async function codeQLVersionToSemantic(parameters: Readonly<TaskParameters>) {
    if (parameters.versionSpec === 'latest') {
        const version = getlatestCodeQLRelease(parameters); 
        return version;
    }
    else {
        return parameters.versionSpec;
    }
}

/**
 * Checks if at least the patch field is present in the version specification
 * @param versionSpec version specification
 */
export function isExactVersion(versionSpec: string): boolean {
    if (!versionSpec) {
        return false;
    }
    const versionNumberParts = versionSpec.split('.');

    return versionNumberParts.length >= 3;
}

async function getlatestCodeQLRelease(parameters: TaskParameters): Promise<string> {
    const auth = `token ${parameters.githubToken}`;
    const additionalHeaders = {};
    if (parameters.githubToken) {
        additionalHeaders['Authorization'] = auth;
    } else {
        task.warning(task.loc('MissingGithubToken'));
    }

    task.debug('Downloading manifest');

    const restClient = new rest.RestClient('vsts-codeql-tool');
    const response: rest.IRestResponse<CodeQLRelease> = await restClient.get(LATEST_URL, {
        additionalHeaders
    });

    if (!response.result) {
        throw new Error(task.loc('ManifestDownloadFailed'));
    }
    const manifest: CodeQLRelease = response.result;
    const version=manifest.tag_name.split('-v')[1]
    return version;
}