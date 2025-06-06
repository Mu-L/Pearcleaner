---
name: Bug
about: For submitting bugs related to the application functionality, not specific 3rd party app issues. Use APP bug report for that
title: "[BUG] ENTER ISSUE TITLE HERE"
labels: ''
assignees: ''

---

### Describe the bug:
A clear and concise description of what the bug is.


### Steps to reproduce:
1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error
   

### Expected behavior:
A clear and concise description of what you expected to happen.


### Info:
 - OS: [e.g. 13.0]
 - Pearcleaner Version: [e.g. 3.x.x]


### Screenshots:
If applicable, add screenshots to help explain your problem.

### Debug Console
1. While Pearcleaner is running, push CMD+D to open the debug console and show captured logs
2. If issue is happening while starting/launching Pearcleaner, pull logs via steps below

### Console Logs (For app startup issues):
 1. Open the Terminal app and run the following command
```
log stream --level debug --style compact --predicate 'subsystem == "com.alienator88.Pearcleaner"'
```
 2. Launch Pearcleaner to reproduce the issue and capture logs
 3. Copy the logs here
