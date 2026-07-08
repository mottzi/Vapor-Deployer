import Vapor

extension Deployer {

    func useCommands() {
        app.asyncCommands.use(UpdateCommand(), as: "update")
        app.asyncCommands.use(RefreshDeployerctlCommand(), as: "refresh-deployerctl")
        app.asyncCommands.use(SetupCommand(), as: "setup")
        app.asyncCommands.use(RemoveCommand(), as: "remove")
        app.asyncCommands.use(ConfigCommand(), as: "config")
        app.asyncCommands.use(VersionCommand(), as: "version")
        app.asyncCommands.use(DeployCommand(), as: "deploy")
        app.asyncCommands.use(ListCommand(), as: "list")
        app.asyncCommands.use(BuildCommand(), as: "build")
        app.asyncCommands.use(RunCommand(), as: "run")
        app.asyncCommands.use(TestCommand(), as: "test")
        app.asyncCommands.use(OutputCommand(), as: "output")
        app.asyncCommands.use(DeleteDeploymentCommand(), as: "delete")
        app.asyncCommands.use(RemoveBinaryCommand(), as: "remove-binary")
    }

}
