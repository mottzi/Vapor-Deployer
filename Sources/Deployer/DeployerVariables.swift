import Vapor

extension Deployer
{
    func useVariables()
    {
        for variable in DeployerVariables.allCases
        {
            guard Environment.get(variable.rawValue) == nil else { continue }
            fatalError("\(variable.rawValue): Environment variable not found.")
        }
    }
}

enum DeployerVariables: String, CaseIterable
{
    case GITHUB_WEBHOOK_SECRET
    case DEPLOY_SECRET

    var value: String { Environment.get(self.rawValue)! }
}
