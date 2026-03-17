import Vapor

extension Deployer {
    
    func useVariables() {
        for variable in Variables.allCases {
            guard Environment.get(variable.rawValue) == nil else { continue }
            fatalError("\(variable.rawValue): Environment variable not found.")
        }
    }
    
    enum Variables: String, CaseIterable {
        case GITHUB_WEBHOOK_SECRET
        case DEPLOY_SECRET
        case PANEL_PASSWORD

        var value: String { Environment.get(self.rawValue)! }
    }
    
}
