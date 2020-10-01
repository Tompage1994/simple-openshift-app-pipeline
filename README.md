# App CI/CD processes

## Deploying Jenkins Agent
`git clone https://github.com/redhat-cop/containers-quickstarts.git`

```
oc process -f containers-quickstarts/.openshift/templates/jenkins-agent-generic-template.yml \
    -p NAME=jenkins-agent-npm \
    -p SOURCE_CONTEXT_DIR=jenkins-agents/jenkins-agent-npm \
    | oc apply -f -
```

## App build
```oc process -f .openshift/app_build.yaml | oc apply -f -  ```

## App deploy
```oc process -f .openshift/app_deploy.yaml | oc apply -f -  ```

## Jenkins
Set up a jenkins job to take in this Jenkinsfile. It will then take in any number of applications by setting parameters