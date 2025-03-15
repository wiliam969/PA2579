pipeline {
    agent any

     environment {
        JULIA_PROJECT = "C:\\src\\PA2579"
        JULIA_DEPOT_PATH = "C:\\src\\PA2579\\.julia"  // Use a custom depot path within the workspace
        PATH = "C:\\Users\\wilia\\AppData\\Local\\Programs\\Julia-1.11.4\\bin;${env.PATH}"
        COVERALLS_CI = "jenkins"
        CI = "true"
        COVERALLS_REPO_TOKEN=["qlUGERZPR64t3RGZgpUAaNIM6dr6VyNFg"]
    }
    
    stages {
       stage('Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/wiliam969/PA2579.git'
            }
        }
        // stage('Setup Julia Environment') {
        //     steps {
        //         bat 'julia.exe --project -e "using Pkg; Pkg.instantiate()"'
        //         // Use bat instead of sh
        //         bat 'julia.exe --project .\\src\\main.jl'

        //     }
        // }
        stage('Run Unit Tests') {
            steps {
                bat 'julia.exe --code-coverage .\\test\\runtests.jl'
            }
        }
        // stage('Run Performance Tests') {
        //     steps {
        //         bat 'julia.exe .\\test\\bmark.jl'
        //     }
        // }

        stage('Submit to Coveralls') {
            steps{
                bat 'julia.exe -e "begin ENV[\"CI\"] = \"true\"; ENV[\"COVERALLS_CI\"] = \"jenkins\"; using Pkg; using Coverage; Coveralls.submit(process_folder()) end"'
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
