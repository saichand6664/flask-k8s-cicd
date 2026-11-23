// Triggered remotely by GitHub Actions (see .github/workflows/trigger-jenkins.yml)
// Flow: checkout -> docker build -> smoke test -> push -> deploy to Kubernetes -> verify

pipeline {
    agent any

    parameters {
        string(name: 'GIT_SHA',    defaultValue: '',            description: 'Commit SHA sent by GitHub Actions')
        string(name: 'GIT_BRANCH', defaultValue: 'main',        description: 'Branch sent by GitHub Actions')
    }

    environment {
        DOCKERHUB_USER = '<saichand6664>'     // <-- change this
        IMAGE_NAME     = "${DOCKERHUB_USER}/flask-app"
        K8S_NAMESPACE  = 'flask-app'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '15'))
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
                script {
                    if (params.GIT_SHA?.trim()) {
                        sh "git checkout ${params.GIT_SHA}"
                    }
                    env.IMAGE_TAG = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    currentBuild.displayName = "#${BUILD_NUMBER} ${env.IMAGE_TAG}"
                }
                echo "Building ${IMAGE_NAME}:${IMAGE_TAG}"
            }
        }

        stage('Docker Build') {
            steps {
                sh """
                    docker build \
                      --build-arg APP_VERSION=${IMAGE_TAG} \
                      -t ${IMAGE_NAME}:${IMAGE_TAG} \
                      -t ${IMAGE_NAME}:latest .
                """
            }
        }

        stage('Smoke Test Image') {
            steps {
                sh """
                    docker rm -f smoke-${BUILD_NUMBER} 2>/dev/null || true
                    docker run -d --name smoke-${BUILD_NUMBER} -p 15000:5000 ${IMAGE_NAME}:${IMAGE_TAG}
                    for i in \$(seq 1 10); do
                      curl -fs http://localhost:15000/health && break
                      sleep 2
                    done
                    curl -fs http://localhost:15000/health
                """
            }
            post {
                always { sh "docker rm -f smoke-${BUILD_NUMBER} || true" }
            }
        }

        stage('Push to Docker Hub') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                                                  usernameVariable: 'DH_USER',
                                                  passwordVariable: 'DH_PASS')]) {
                    sh '''
                        echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
                        docker push ${IMAGE_NAME}:${IMAGE_TAG}
                        docker push ${IMAGE_NAME}:latest
                        docker logout
                    '''
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                    sh """
                        kubectl apply -f k8s/service.yaml
                        sed "s|IMAGE_PLACEHOLDER|${IMAGE_NAME}:${IMAGE_TAG}|g" k8s/deployment.yaml | kubectl apply -f -
                        kubectl -n ${K8S_NAMESPACE} rollout status deployment/flask-app --timeout=120s
                    """
                }
            }
        }

        stage('Verify') {
            steps {
                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                    sh "kubectl -n ${K8S_NAMESPACE} get pods,svc -o wide"
                }
            }
        }
    }

    post {
        success {
            echo "Deployed ${IMAGE_NAME}:${IMAGE_TAG} -> http://<homelab-ip>:30080"
        }
        failure {
            withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                // Roll back only if a deploy had started
                sh "kubectl -n ${K8S_NAMESPACE} rollout undo deployment/flask-app || true"
            }
        }
        always {
            sh "docker image prune -f || true"
        }
    }
}
