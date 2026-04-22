import Vapor
import Foundation

/// Parses the application's Package.swift to identify and prompt for the executable product to deploy.
struct ResolveProductStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Resolving executable product"

    func run() async throws {

        let manifestPath = "\(paths.appDirectory)/Package.swift"
        let products = inferExecutableProducts(from: manifestPath)
        
        context.executableProducts = products
        context.productName = selectProduct(from: products)
    }

}

extension ResolveProductStep {

    private func inferExecutableProducts(from manifestPath: String) -> [String] {

        guard let manifestContent = try? String(contentsOfFile: manifestPath, encoding: .utf8) else { return [] }
        
        var names = Set<String>()
        var inExecutableProduct = false
        var inExecutableTarget = false

        for line in manifestContent.split(whereSeparator: \.isNewline).map(String.init) {
            if line.range(of: #"\.executable\s*\("#, options: .regularExpression) != nil { inExecutableProduct = true }
            if line.range(of: #"\.executableTarget\s*\("#, options: .regularExpression) != nil { inExecutableTarget = true }

            if inExecutableProduct || inExecutableTarget, let name = extractName(from: line) {
                names.insert(name)
                inExecutableProduct = false
                inExecutableTarget = false
            } else if line.contains(")") {
                inExecutableProduct = false
                inExecutableTarget = false
            }
        }

        return names.sorted()
    }

    private func selectProduct(from products: [String]) -> String {

        switch products.count {
        case 0:
            console.warning("Could not infer an executable product from Package.swift.")
            return console.askValidated(
                "Executable product name",
                warning: "Executable product name may contain only letters, numbers, dots, dashes, and underscores.",
                validate: InputValidator.isSafeName
            )
        case 1:
            console.print("Using executable product '\(products[0])' inferred from Package.swift.")
            return products[0]
        default:
            return console.choose("Executable product name".consoleText(), from: products)
        }
    }

}

extension ResolveProductStep {

    private func extractName(from line: String) -> String? {

        guard let regex = try? NSRegularExpression(pattern: #"name\s*:\s*"([^"]+)""#) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range) else { return nil }
        guard let nameRange = Range(match.range(at: 1), in: line) else { return nil }
        
        return String(line[nameRange])
    }

}
