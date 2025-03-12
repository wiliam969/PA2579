pipeline {
    agent any

    environment {
        // Set the project path (adjust if needed)
        JULIA_PROJECT = "${WORKSPACE}"
    }
    
    stages {
        stage('Checkout') {
            steps {
                // Clone your repository from Git
                git 'https://github.com/wiliam969/PA2579.git'
            }
        }
        stage('Setup Julia Environment') {
            steps {
                // Instantiate your Julia project dependencies
                sh 'julia --project=@. -e "using Pkg; Pkg.instantiate()"'
            }
        }
        stage('Run Tests') {
            steps {
                // Run your MILP model tests (or main script)
                sh 'julia --project=@. dsm_milp_with_graph.jl'
            }
        }
    }
    post {
        always {
            // Archive artifacts (for example, generated graphs or test results)
            archiveArtifacts artifacts: '**/DSM_solution.png', allowEmptyArchive: true
            // You could also publish test reports if your tests output an XML report
            // junit 'test_results.xml'
        }
        failure {
            // Add notifications (email, Slack, etc.) if tests fail
            echo "Build failed. Check Jenkins logs for details."
        }
    }
}
