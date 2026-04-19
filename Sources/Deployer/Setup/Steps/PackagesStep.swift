import Vapor
import Foundation

struct PackagesStep: SetupStep {

    let title = "Installing base packages"

    func run(context: SetupContext, console: any Console) async throws {
        let gccMajor = await detectGCCMajor()
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
            if await Shell.run(["dpkg", "-s", package]).exitCode != 0 {
                missing.append(package)
            }
        }

        guard !missing.isEmpty else {
            console.print("All required packages already installed.")
            return
        }

        try await Shell.runThrowing(["apt-get", "-qq", "update"])
        try await Shell.runThrowing(["apt-get", "-y", "-qq", "install"] + missing)
        console.print("Base packages installed.")
    }

    private func detectGCCMajor() async -> String {
        let output = await Shell.run(["apt-cache", "show", "gcc"]).output
        for line in output.split(whereSeparator: \.isNewline) {
            guard line.hasPrefix("Version:") else { continue }
            let version = String(line.dropFirst("Version:".count)).trimmed
            let normalized = version.split(separator: ":").last.map(String.init) ?? version
            return normalized.split(separator: ".").first.map(String.init) ?? "13"
        }

        return "13"
    }

}
