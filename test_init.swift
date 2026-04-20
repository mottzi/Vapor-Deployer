protocol SetupStep {
    init(context: String, console: String)
}

struct MyStep: SetupStep {
    let title = "My Step"
    let context: String
    let console: String
}

let types: [any SetupStep.Type] = [MyStep.self]
let instances = types.map { $0.init(context: "ctx", console: "con") }
print(instances)
