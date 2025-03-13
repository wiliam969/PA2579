pipeline {
    agent any

    environment {
        // Set the project path (adjust if needed)
        JULIA_PROJECT = "${WORKSPACE}"
        PATH = "C:\\Users\\wilia\\AppData\\Local\\Microsoft\\WindowsApps;${env.PATH}"
    }
    
    stages {
       stage('Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/wiliam969/PA2579.git'
            }
        }
        stage('Setup Julia Environment') {
            steps {
                // Use bat instead of sh
                bat 'julia.exe --project -e "using Pkg; Pkg.instantiate()"'
            }
        }
        stage('Run Tests') {
            steps {
                bat 'julia.exe --project -e "using Pkg; Pkg.test()"'
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
