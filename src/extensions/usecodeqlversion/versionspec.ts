import * as semver from 'semver';


export function codeQLVersionToSemantic(versionSpec: string) {
    return versionSpec
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
