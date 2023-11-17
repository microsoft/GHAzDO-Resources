
import * as fs from "fs";
import * as os from 'os';
import * as path from 'path';
import * as semver from 'semver';
import * as rest from 'typed-rest-client';
import * as task from 'azure-pipelines-task-lib/task';
import * as tool from 'azure-pipelines-tool-lib/tool';

import { getPlatform, Platform } from './taskutil';
import { TaskParameters, CodeQLRelease, CodeQLBundleAsset } from './interfaces';
import { tinyGuid } from 'azure-pipelines-tasks-utility-common/tinyGuidUtility'

const MANIFEST_URL = 'https://api.github.com/repos/github/codeql-action/releases';

/**
 * Installs specified CodeQL version.
 * This puts CodeQL binaries in the tools directory for later use.
 * @param versionSpec version specification.
 * @param parameters task parameters.
 */
export async function installCodeQLVersion(versionSpec: string, parameters: TaskParameters) {
    const CodeQLInstallerDir: string = await downloadCodeQLVersion(versionSpec, parameters);

    task.debug(`Extracted CodeQL archive to ${CodeQLInstallerDir}`);
}

/**
 * Downloads and extracts CodeQL file for the host system.
 * Looks for CodeQL files from the github actions CodeQL versions manifest.
 * Throws if file is not found.
 * @param versionSpec version specification.
 * @param parameters task parameters.
 * @returns path to the extracted CodeQL archive.
 */
async function downloadCodeQLVersion(versionSpec: string, parameters: TaskParameters): Promise<string> {
    const auth = `token ${parameters.githubToken}`;
    const additionalHeaders = {};
    if (parameters.githubToken) {
        additionalHeaders['Authorization'] = auth;
    } else {
        task.warning(task.loc('MissingGithubToken'));
    }

    task.debug('Downloading manifest');

    const restClient = new rest.RestClient('vsts-codeql-tool');
    const response: rest.IRestResponse<CodeQLRelease[]> = await restClient.get(MANIFEST_URL, {
        additionalHeaders
    });

    if (!response.result) {
        throw new Error(task.loc('ManifestDownloadFailed'));
    }

    const manifest: CodeQLRelease[] = response.result;

    const matchingCodeQLFile: CodeQLBundleAsset | null = findCodeQLFile(manifest, versionSpec, parameters);
    if (matchingCodeQLFile === null) {
        throw new Error(task.loc('DownloadNotFound', versionSpec));
    }

    task.debug(`Found matching file for system: ${matchingCodeQLFile.name}`);

    const CodeQLArchivePath: string = await tool.downloadTool(matchingCodeQLFile.browser_download_url, matchingCodeQLFile.name, null, additionalHeaders);

    task.debug(`Downloaded CodeQL archive to ${CodeQLArchivePath}`);

    // Extract
    var installationPath = path.join(task.getVariable('Agent.ToolsDirectory'), "CodeQL", versionSpec, os.arch());
    task.mkdirP(installationPath)
    console.log(task.loc("ExtractingPackage", CodeQLArchivePath));
    try {
        let tempDirectory = task.getVariable('Agent.TempDirectory');
        let extDirectory = path.join(tempDirectory, tinyGuid());
        var extPath = (path.extname(CodeQLArchivePath) === '.zip') ? await tool.extractZip(CodeQLArchivePath, installationPath) : await tool.extractTar(CodeQLArchivePath,installationPath);
        task.writeFile(path.join(installationPath, 'pinned-version'), '');
        task.writeFile(installationPath + '.complete', '');
        return extPath;
    }
    catch (ex) {
        throw task.loc("FailedWhileExtractingPackage", ex);
        return '';
    }
}

/**
 * Looks through the releases of the manifest and tries to find the one that has matching version.
 * Skips unstable releases if `allowUnstable` is set to false.
 * @param manifest CodeQL releases manifest containing CodeQL releases.
 * @param versionSpec version specification.
 * @param parameters task parameters.
 * @returns matching CodeQL file for the system.
 */
function findCodeQLFile(manifest: CodeQLRelease[], versionSpec: string, parameters: TaskParameters): CodeQLBundleAsset | null {
    for (const release of manifest) {
        if (!parameters.allowUnstable && (release.prerelease === true || release.draft === true)) {
            continue;
        }

        const version=release.tag_name.split('-v')[1]
        if (!semver.satisfies(version, versionSpec)) {
            continue;
        }

        const matchingFile: CodeQLBundleAsset | undefined = release.assets.find(
            (file: CodeQLBundleAsset) => matchesOs(file)
        );
        if (matchingFile === undefined) {
            continue;
        }

        return matchingFile;
    }

    return null;
}

/**
 * Checks whether the passed file matches the host OS by comparing platform, arch, and platform version if present.
 * @param file CodeQL file info.
 * @returns whether the file matches the host OS.
 */
function matchesOs(file: CodeQLBundleAsset): boolean {
    switch(file.name) {
        case 'codeql-bundle-osx64.tar.gz':
            if (getPlatform() == Platform.MacOS) {
                return true;
            }
        case 'codeql-bundle-linux64.tar.gz':
            if (getPlatform() == Platform.Linux) {
                return true;
            }
        case 'codeql-bundle-win64.zip':
            if (getPlatform() == Platform.Windows) {
                return true;
            }
        default : {
            break;
        }
        return false;
    }
}
