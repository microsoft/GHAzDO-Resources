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

<img width="800" alt="1check" src="https://github.com/microsoft/GHAzDO-Resources/assets/106392052/300c4794-a709-4340-acef-a134a6556e58">


Clicking the error will bring you to the CIVerify Pipeline run. You will see two errors listed for the Pipeline. One referencing to the new bad code, one just noting that CIVerify failed. 

<img width="800" alt="2errorlogs" src="https://github.com/microsoft/GHAzDO-Resources/assets/106392052/2dcb1ca7-13f4-4a96-872b-e83a1b9381a4">


Open up the logs for the first error. You will be able to see the CodeQL error message, alert id and also have a link to the new alert that was detected. 

<img width="800" alt="3logtext" src="https://github.com/microsoft/GHAzDO-Resources/assets/106392052/7f634b98-d34a-4b40-ae9e-37f4cfb61fc4">


Select the link and jump to the new alert.  Review the alert, fix or dismiss this alert. 


<img width="800" alt="ReviewCloseAlert" src="https://github.com/microsoft/GHAzDO-Resources/assets/106392052/b7ec3938-a1cf-4001-9e6d-59c62bfdc873">



Re-queue the CIVerify check again in the PR. 
This time the check should pass with not issue.    

<img width="800" alt="CheckOk" src="https://github.com/microsoft/GHAzDO-Resources/assets/106392052/021403d8-96dd-4246-a7cc-9ee95df88a04">


