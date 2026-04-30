import Foundation

extension Shell {
    
    static func getCurrentCheckout(in directory: String) async throws -> GitCheckout {
        
        let commitID = try await runThrowing("git rev-parse HEAD", directory: directory).trimmed
        let commitMessage = try await runThrowing("git log -1 --pretty=%s HEAD", directory: directory).trimmed
        let committedAtRaw = try await runThrowing("git show -s --format=%ct HEAD", directory: directory).trimmed
        
        guard
            let committedAtSeconds = TimeInterval(committedAtRaw),
            commitID.isEmpty == false,
            commitMessage.isEmpty == false
        else {
            throw Shell.Error(command: "git checkout inspection", output: "Failed to parse current checkout metadata.")
        }
        
        let branch = await getCurrentBranch(in: directory)
        
        return GitCheckout(
            commitID: commitID,
            commitMessage: commitMessage,
            branch: branch,
            committedAt: Date(timeIntervalSince1970: committedAtSeconds)
        )
    }
    
    static func getCurrentBranch(in directory: String) async -> String {
        
        let symbolicBranch = await run("git symbolic-ref -q --short HEAD", directory: directory).output.trimmed
        if symbolicBranch.isEmpty == false {
            return "refs/heads/\(symbolicBranch)"
        }
        
        let remoteBranches = await run("git branch -r --contains HEAD --format='%(refname:short)'", directory: directory).output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmed }
            .filter {
                !$0.isEmpty &&
                !$0.contains("->") &&
                !$0.hasSuffix("/HEAD")
            }
        
        if let originBranch = remoteBranches.first(where: { $0.hasPrefix("origin/") }) {
            return "refs/heads/\(originBranch.dropFirst("origin/".count))"
        }
        
        return remoteBranches.first ?? "HEAD"
    }
    
}

struct GitCheckout: Sendable {
    
    let commitID: String
    let commitMessage: String
    let branch: String
    let committedAt: Date
    
}
