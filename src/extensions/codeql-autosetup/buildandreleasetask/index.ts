import tl = require('azure-pipelines-task-lib/task');
import * as path from "path";
import * as os from "os";
import * as fs from "fs";
import * as azdev from "azure-devops-node-api";
import * as lim from "azure-devops-node-api/interfaces/LocationsInterfaces";
import * as ProjectAnalysisApi from "azure-devops-node-api/ProjectAnalysisApi";
import * as ProjectAnalysisInterfaces from "azure-devops-node-api/interfaces/ProjectAnalysisInterfaces";

async function run() {
    try {
        
        // Check for presence of CodeQL before running
        console.log(`Tool Cache Directory: ${tl.getVariable('Agent.ToolsDirectory')}`);
        const versions: string[] = [];
        const arch = os.arch();
        const toolPath = path.join(tl.getVariable('Agent.ToolsDirectory')!, "CodeQL");
        if (fs.existsSync(toolPath)) {
            const children = fs.readdirSync(toolPath);
            for (const child of children) {
                const fullPath = path.join(toolPath, child, arch || "");
                if (fs.existsSync(fullPath) && fs.existsSync(`${fullPath}.complete`)) {
                    versions.push(child);
                }
            }
        }
        if (versions.length === 0) {throw new Error(`CodeQL not installed`);}

        const completeFile = path.resolve(tl.getVariable('Agent.ToolsDirectory')!, 'CodeQL', );

        if (!fs.existsSync(completeFile)) {
            throw new Error(`CodeQL not installed`);
        }

        const uriBase = tl.getVariable('System.CollectionUri') as string;
        const projectId = tl.getVariable('System.TeamProjectId') as string ;
        const repositoryId = tl.getVariable('Build.Repository.ID') as string;
        tl.setVariable('AdvancedSecurity.CodeQL.Autoconfig', 'failed');
        const token = tl.getVariable('System.AccessToken') as string;

        console.log(`Using Project ${projectId}`);

        // Authenticating and connecting
        let authHandler = azdev.getPersonalAccessTokenHandler(token); 
        let webapi = new azdev.WebApi(uriBase, authHandler, undefined);    
        let connData: lim.ConnectionData = await webapi.connect();

        // Analytics Access
        let Analysis: ProjectAnalysisApi.IProjectAnalysisApi = await webapi.getProjectAnalysisApi();
        let languageMetrics : ProjectAnalysisInterfaces.ProjectLanguageAnalytics = await Analysis.getProjectLanguageAnalytics(projectId);
        let repos : ProjectAnalysisInterfaces.RepositoryLanguageAnalytics[] = languageMetrics.repositoryLanguageAnalytics as ProjectAnalysisInterfaces.RepositoryLanguageAnalytics[];
        console.log(`Found ${repos.length} repositories`);

        let repository :ProjectAnalysisInterfaces.RepositoryLanguageAnalytics = repos.find(repo  => repo.id === repositoryId) as ProjectAnalysisInterfaces.RepositoryLanguageAnalytics;
        console.log(`Found ${repository.name}`);

        let language : ProjectAnalysisInterfaces.LanguageStatistics[] = repository.languageBreakdown as ProjectAnalysisInterfaces.LanguageStatistics[];

        // Language Metrics
        let languages : Set<string> = new Set<string>();

        console.log(`Found ${language.length} languages`);

        language.forEach(lang => {
            console.log(`Language: ${lang.name}`);
            switch(lang.name){
                case "Ruby": languages.add("ruby");break;
                case "JavaScript": languages.add("javascript");break;
                case "Python": languages.add("python");break;
                case "TypeScript": languages.add("javascript");break;
                case "ruby": languages.add("ruby");break;
                case "go": languages.add("go");break;
                case "golang": languages.add("go");break;
                default: break;
            }
            //console.log(languages);
        });

        if (languages.size > 0) {
            console.log(`Configured ${languages.size} languages`);
            let languageList = "";
            let strArray = new Array<string>();
            languages.forEach(lang => {strArray.push(lang)});
            languageList = strArray.join(",");
            tl.setVariable('AdvancedSecurity.CodeQL.Language', languageList);
            //console.log(`Language List: ${languageList}`);
            tl.setVariable('AdvancedSecurity.CodeQL.Autoconfig', 'true');
        }
        else {
            tl.setVariable('AdvancedSecurity.CodeQL.Autoconfig', 'false');
            console.log(`No languages found`);
        }
    }
    catch (err) {
        tl.setVariable('AdvancedSecurity.CodeQL.Autoconfig', 'failed');
        console.log('CodeQL Autoconfig failed');
    }
}

run();