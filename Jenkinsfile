pipeline {

    agent {
        // label "" also could have been 'agent any' - that has the same meaning.
        label "master"
    }

    environment {
        // Global Vars
        PIPELINES_NAMESPACE = "app-ci-cd"
        APP_NAME = "test-app"

        JENKINS_TAG = "${JOB_NAME}.${BUILD_NUMBER}".replace("/", "-")
        JOB_NAME = "${JOB_NAME}".replace("/", "-")

        GIT_SSL_NO_VERIFY = true
        GIT_CREDENTIALS = credentials('app-ci-cd-jenkins-git-password')

        SCM_DOMAIN = "gitlab-labs-ci-cd.apps.somedomain.com"
        SCM_PROJECT = "test-app"
    }

    // The options directive is for configuration that applies to the whole job.
    options {
        buildDiscarder(logRotator(numToKeepStr: '50', artifactNumToKeepStr: '1'))
        timeout(time: 15, unit: 'MINUTES')
        ansiColor('xterm')
        timestamps()
    }

    stages {
        stage("node-build") {
            agent {
                node {
                    label "jenkins-agent-npm"
                }
            }
            steps {
                sh 'printenv'

                echo '### Install deps with unsafe perms ###'
                sh 'npm install node-sass --unsafe-perm'

                echo '### Install deps ###'
                sh 'npm install'

                // echo '### Running tests ###'
                // sh 'npm run test'

                echo '### Run Build ###'
                sh 'npm run build:dev'
            }
        }

        stage("node-bake") {
            agent {
                node {
                    label "master"
                }
            }
            steps {
                echo '### Create Linux Container Image from package ###'
                sh  '''
                        oc project ${PIPELINES_NAMESPACE} # probs not needed
                        oc patch bc ${APP_NAME} -p "{\\"spec\\":{\\"output\\":{\\"to\\":{\\"kind\\":\\"ImageStreamTag\\",\\"name\\":\\"${APP_NAME}:${JENKINS_TAG}\\"}}}}"
                        oc start-build ${APP_NAME} --from-dir=. --follow
                    '''
            }
        }

        stage("node-deploy") {
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
                openshiftVerifyDeployment depCfg: env.APP_NAME,
                    namespace: env.PROJECT_NAMESPACE,
                    replicaCount: '1',
                    verbose: 'false',
                    verifyReplicaCount: 'true',
                    waitTime: '',
                    waitUnit: 'sec'
            }
        }
    }
    post {
        always {
            archiveArtifacts "**"
        }
    }
}
