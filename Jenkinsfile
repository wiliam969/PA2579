pipeline {
    agent any

    environment {
        // Set the project path (adjust if needed)
        JULIA_PROJECT = "${WORKSPACE}"
    }
    
    stages {
        stage('Checkout') {
            steps {
                // Clone your repository from Git using the built-in git step
                git url: 'https://github.com/wiliam969/PA2579.git'
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
        }
        failure {
            echo "Build failed. Check Jenkins logs for details."
        }
    }
}
