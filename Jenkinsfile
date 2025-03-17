pipeline {
    agent any

     environment {
        JULIA_PROJECT = "C:\\src\\PA2579"
        JULIA_DEPOT_PATH = "C:\\src\\PA2579\\.julia"  // Use a custom depot path within the workspace
        PATH = "C:\\Users\\wilia\\AppData\\Local\\Programs\\Julia-1.11.4\\bin; C:\\appl;${env.PATH}"
        COVERALLS_CI = "jenkins"
        CI = true
        COVERALLS_REPO_TOKEN="qlUGERZPR64t3RGZgpUAaNIM6dr6VyNFg"
    }
    
    stages {
       stage('Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/wiliam969/PA2579.git'
            }
        }
        stage('Build Julia Environment') {
            steps {
                bat 'julia.exe --project -e "using Pkg; Pkg.update(); Pkg.instantiate()"'
            }
        }
        stage('Run Unit Tests') {
            steps {
                bat 'julia.exe --code-coverage .\\test\\runtests.jl'
            }
        }
        stage('Run Static Code Analysis') {
            steps {
                bat 'julia.exe --project -e "using Pkg; using JET; report_file("src\\main.jl")"'
            }
        }
        stage('Run Performance Tests') {
            steps {
                bat 'julia.exe .\\test\\bmark.jl'
            }
        }
        stage('Submit to Coveralls') {
            steps{
                bat 'julia.exe .\\test\\submit_coveralls.jl'
                bat 'coverage.bat'
            }
        }
        stage('Run PGM') {
            steps {
                bat 'julia.exe --project .\\src\\main.jl'
            }
        }

    }
    post {
        always {
            // Archive artifacts (for example, generated graphs or test results)
            archiveArtifacts artifacts: 'build/**.png', allowEmptyArchive: true
        }
        failure {
            echo "Build failed. Check Jenkins logs for details."
        }
    }
}
