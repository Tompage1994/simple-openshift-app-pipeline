pipeline {

    agent {
        // label "" also could have been 'agent any' - that has the same meaning.
        label "master"
    }

    environment {
        // Global Vars
        // PIPELINES_NAMESPACE = PARAM
        // PROJECT_NAMESPACE = PARAM
        // APP_NAME = PARAM

        // Can be parameterised
        SOURCE_REPOSITORY_NAME = "${APP_NAME}"

        // SOURCE_REPOSITORY_REF = PARAM
        // ENVIRONMENT = PARAM (dev,stg,prod)

        JENKINS_TAG = "${BUILD_NUMBER}"

        // May need to add these in for an internal SCM
        // GIT_SSL_NO_VERIFY = true
        // GIT_CREDENTIALS = credentials('app-ci-cd-jenkins-git-password')

        // Need to hardcode this when in internal SCM
        // WILDCARD_ROUTE = "apps.ocp.example.com"
        // SOURCE_REPOSITORY_URL = //param
    }

    // The options directive is for configuration that applies to the whole job.
    options {
        buildDiscarder(logRotator(numToKeepStr: '50', artifactNumToKeepStr: '1'))
        timeout(time: 15, unit: 'MINUTES')
    }

    stages {
        stage("App Build") {
            agent {
                node {
                    label "jenkins-agent-npm"
                }
            }
            steps {
                dir(SOURCE_REPOSITORY_NAME) {
                    git url: "${SOURCE_REPOSITORY_URL}", branch: "${SOURCE_REPOSITORY_REF}"
                    sh 'printenv'

                    // echo '### Install deps with unsafe perms ###'
                    // sh 'npm install node-sass --unsafe-perm'

                    echo '### Install deps ###'
                    sh 'npm install'

                    // echo '### Running tests ###'
                    // sh 'npm run test'

                    echo '### Run Build ###'
                    sh 'npm run build:${ENVIRONMENT}'

                    stash name: "dist", includes: "dist/*"
                }
            }
        }

        stage("Prepare OpenShift Environment") {
            agent {
                node {
                    label "jenkins-agent-helm"
                }
            }
            steps {
                script {
                    if (ENVIRONMENT == "dev") {
                        env.HOSTNAME = "${APP_NAME}-dev"
                    } else if (ENVIRONMENT == "stg") {
                        env.HOSTNAME = "${APP_NAME}-stg"
                    } else if (ENVIRONMENT == "prod") {
                        env.HOSTNAME = "${APP_NAME}"
                    }
                }

                sh "helm template helm/app_build --set name=${APP_NAME} -n ${PIPELINES_NAMESPACE} | oc apply -n ${PIPELINES_NAMESPACE}  -f -"
                sh "helm template helm/app_deploy --set name=${APP_NAME},namespace=${PROJECT_NAMESPACE},hostname=${HOSTNAME},wildcard_route=${WILDCARD_ROUTE} -n ${PROJECT_NAMESPACE} | oc apply -n ${PROJECT_NAMESPACE}  -f -"
            }
        }

        stage("App Bake") {
            agent {
                node {
                    label "master"
                }
            }
            steps {
                unstash "dist"

                echo '### Create Linux Container Image from package ###'
                sh  '''
                        oc project ${PIPELINES_NAMESPACE} # probs not needed
                        oc patch bc ${APP_NAME} -p "{\\"spec\\":{\\"output\\":{\\"to\\":{\\"kind\\":\\"ImageStreamTag\\",\\"name\\":\\"${APP_NAME}:${JENKINS_TAG}\\"}}}}"
                        oc start-build ${APP_NAME} --from-dir=. --follow
                    '''
            }
        }

        stage("App Deploy") {
            agent {
                node {
                    label "master"
                }
            }
            steps {
                echo '### tag image for namespace ###'
                sh  '''
                    oc project ${PROJECT_NAMESPACE}
                    oc tag ${PIPELINES_NAMESPACE}/${APP_NAME}:${JENKINS_TAG} ${PROJECT_NAMESPACE}/${APP_NAME}:${JENKINS_TAG}
                    '''
                echo '### set env vars and image for deployment ###'
                sh '''
                    oc set image dc/${APP_NAME} ${APP_NAME}=docker-registry.default.svc:5000/${PROJECT_NAMESPACE}/${APP_NAME}:${JENKINS_TAG}
                    oc rollout latest dc/${APP_NAME}
                '''
                echo '### Verify OCP Deployment ###'
                script {
                    env.JENKINS_SA_TOKEN = sh (
                        script: 'oc whoami -t',
                        returnStdout: true
                    ).trim()
                }
                openshiftVerifyDeployment depCfg: env.APP_NAME,
                    namespace: env.PROJECT_NAMESPACE,
                    replicaCount: '1',
                    verbose: 'false',
                    verifyReplicaCount: 'true',
                    waitTime: '',
                    waitUnit: 'sec',
                    authToken: env.JENKINS_SA_TOKEN
            }
        }
    }
}
