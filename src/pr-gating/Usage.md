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



Clicking the error will bring you to the CIVerify Pipeline run. You will see two errors listed for the Pipeline. One referencing to the new bad code, one just noting that CIVerify failed. 


Open up the logs for the first error. You will be able to see the CodeQL error message, alert id and also have a link to the new alert that was detected. 


Select the link and jump to the new alert. 
Review the alert, fix or dismiss this alert. 



Re-queue the CIVerify check again in the PR. 
This time the check should pass with not issue.    



