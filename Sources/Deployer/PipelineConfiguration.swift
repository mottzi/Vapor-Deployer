import Fluent
import Vapor

public struct PipelineConfiguration: Sendable
{
    let productName: String
    let workingDirectory: String
    let buildConfiguration: String
    var pusheventPath: [PathComponent]
    
    public init(
        productName: String,
        workingDirectory: String,
        buildConfiguration: String,
        pusheventPath: [PathComponent]
    ) {
        self.productName = productName
        self.workingDirectory = workingDirectory
        self.buildConfiguration = buildConfiguration
        self.pusheventPath = pusheventPath
    }
}
