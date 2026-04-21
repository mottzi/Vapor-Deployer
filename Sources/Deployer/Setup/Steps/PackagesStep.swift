import Vapor

/// Installs required dependencies for Swift compilation of the target Vapor application and provision its server environment.
struct PackagesStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Installing base packages"

    func run() async throws {
        
        let gccMajor = await getGCCVersion()
        
        var packages = [
            "binutils",
            "gnupg2",
            "libc6-dev",
            "libcurl4-openssl-dev",
            "libedit2",
            "libgcc-\(gccMajor)-dev",
            "libncurses-dev",
            "libpython3-dev",
            "libsqlite3-0",
            "libstdc++-\(gccMajor)-dev",
            "libxml2-dev",
            "libz3-dev",
            "pkg-config",
            "tzdata",
            "unzip",
            "zip",
            "zlib1g-dev",
            "ca-certificates",
            "certbot",
            "curl",
            "git",
            "jq",
            "nginx",
            "openssl",
            "openssh-client"
        ]

        if context.serviceManagerKind == .supervisor {
            packages.append("supervisor")
        }

        var missing: [String] = []
        
        for package in packages {
            if await Shell.run("dpkg", ["-s", package]).exitCode != 0 {
                missing.append(package)
            }
        }

        guard !missing.isEmpty else {
            console.print("All required packages already installed.")
            return
        }

        try await Shell.runThrowing("apt-get", ["-qq", "update"])
        try await Shell.runThrowing("apt-get", ["-y", "-qq", "install"] + missing)
        
        console.print("Base packages installed.")
    }

    /// Determines the major version of the C compiler.
    private func getGCCVersion() async -> String {
        
        let aptOutput = await Shell.run("apt-cache", ["policy", "gcc"]).output
        
        for line in aptOutput.split(whereSeparator: \.isNewline) {
            let trimmedLine = String(line).trimmed
            guard trimmedLine.hasPrefix("Candidate:") else { continue }
            
            let fullVersion = trimmedLine.dropFirst("Candidate:".count).trimmingCharacters(in: .whitespaces)
            let baseVersion = fullVersion.split(separator: ":").last.map(String.init) ?? fullVersion
            
            return baseVersion.split(separator: ".").first.map(String.init) ?? "13"
        }

        return "13"
    }

}
