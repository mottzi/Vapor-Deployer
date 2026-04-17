import Vapor

extension Deployer {
    
    func useVariables() throws {
        for variable in Variables.allCases {
            guard Environment.get(variable.rawValue) == nil else { continue }
            throw DeployerConfiguration.LoadError.invalidField(
                "environment.\(variable.rawValue)",
                "environment variable not found"
            )
        }
    }
    
    enum Variables: String, CaseIterable {
        case GITHUB_WEBHOOK_SECRET
        case PANEL_PASSWORD

        var value: String { Environment.get(self.rawValue)! }
    }
    
}
