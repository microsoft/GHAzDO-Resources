export interface TaskParameters {
    versionSpec: string,
    disableDownloadFromRegistry: boolean,
    allowUnstable: boolean,
    addToPath: boolean,
    githubToken?: string
}

export interface CodeQLRelease {
    url:              string;
    assets_url:       string;
    upload_url:       string;
    html_url:         string;
    id:               number;
    author:           any;
    node_id:          string;
    tag_name:         string;
    target_commitish: string;
    name:             string;
    draft:            boolean;
    prerelease:       boolean;
    created_at:       Date;
    published_at:     Date;
    assets:           CodeQLBundleAsset[];
    tarball_url:      string;
    zipball_url:      string;
    body:             string;
    reactions?:       any;
}

export interface CodeQLBundleAsset {
    url:                  string;
    id:                   number;
    node_id:              string;
    name:                 string;
    label:                null | string;
    uploader:             any;
    content_type:         string;
    state:                string;
    size:                 number;
    download_count:       number;
    created_at:           Date;
    updated_at:           Date;
    browser_download_url: string;
}
