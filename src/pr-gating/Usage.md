## Usage

After setup, all PRs into main will have CIVerify as a PR verification check.

For the code in this repo, one way to test the setup is to create a new branch based on main. Update the index.js file in the new branch to include these lines, after line 34

```
// This code will generate a CodeQL rate limit alert
app.get('/mybadcode', (req, res) => {
  res.sendFile('form.html', { root: __dirname });
});
```

Save the file and create a new Pull Request from the new branch into main. 

The CIVerify pipeline will run as part of the checks for this PR. This check will fail and issues with the new code will be reported.

<img width="800" alt="CIVerify fail" src="https://github.com/microsoft/GHAzDO-Resources/assets/106392052/99dbf004-7d45-4d53-a6a5-8a9027ac980c">

An annotation has also been added to the file that contains the CodeQL issue. 

<img width="800" alt="PR annotation" src="https://github.com/microsoft/GHAzDO-Resources/assets/106392052/4a3d1a1b-722d-4596-889e-ab3190350ae4">

The annotation will be in the name of the person that created the PAT that is being used by the pipeline (GHAZDO_PRGATING_PAT). 
Open the 'See details here' link and review the alert. 

In most scenarios, the best option will be to fix the code so that the alert disapears. If this is a false possitive and you have the access rights, you can dismiss the alert. 

<img width="800" alt="Alert review" src="https://github.com/microsoft/GHAzDO-Resources/assets/106392052/caad17cd-9c3d-431a-9045-ad681bbc8da8">

You should also close the comment that was added to the PR.

<img width="800" alt="Close comment" src="https://github.com/microsoft/GHAzDO-Resources/assets/106392052/9a75487a-6ce0-4962-ae57-4c0708bc8f9b">

Re-queue the CIVerify check again in the PR. 
This time the check should pass with not issue.    

<img width="800" alt="CheckOk" src="https://github.com/microsoft/GHAzDO-Resources/assets/106392052/021403d8-96dd-4246-a7cc-9ee95df88a04">


