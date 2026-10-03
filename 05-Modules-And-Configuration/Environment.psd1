@{
    Repository = @{
        Name = 'TrainingRepository'
        Branch = 'main'
        TokenName = 'SampleTrainingToken'
        RemoteName = 'origin'
    }
    Paths = @{
        KeyFolder = '.sample-git-keys'
        PackageFolder = '.sample-packages'
        DeploymentFolder = '.sample-deployments'
        LogFolder = '.sample-logs'
    }
    Deployment = @{
        EnvironmentName = 'Training'
        PackageName = 'TrainingRepositoryPackage'
        Version = '1.0.0'
    }
}
