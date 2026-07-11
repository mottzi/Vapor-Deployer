import Foundation
import Mist
import Vapor

extension Panel {
    
    /// Registers Mist's embedded browser runtime and Deployer-owned static assets under the configured panel route prefix.
    func registerAssetRoutes(on router: RoutesBuilder) {
        for asset in MistAsset.allCases {
            let metadata = MistAssets.metadata(for: asset)
            let path = PathComponent(stringLiteral: metadata.filename)

            for method in [HTTPMethod.GET, .HEAD] {
                router.on(method, path) { request -> Response in
                    mistAssetResponse(for: request, metadata: metadata)
                }
            }
        }

        for asset in ["deployer.css", "mottzi.png", "deployer.png", "deployer.ico"] {
            router.get(PathComponent(stringLiteral: asset)) { request async throws -> Response in
                let filePath = request.application.directory.publicDirectory + "deployer/" + asset
                return try await request.fileio.asyncStreamFile(at: filePath)
            }
        }

        router.get("styles", ":filename") { request async throws -> Response in
            guard let filename = request.parameters.get("filename"),
                  filename.hasSuffix(".css"),
                  !filename.contains("/") else { throw Abort(.notFound) }
            let filePath = request.application.directory.publicDirectory + "deployer/styles/" + filename
            return try await request.fileio.asyncStreamFile(at: filePath)
        }
    }

    private func mistAssetResponse(for request: Request, metadata: MistAssetMetadata) -> Response {
        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .contentType, value: metadata.mediaType)
        headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
        headers.replaceOrAdd(name: .eTag, value: metadata.etag)

        guard !request.headers.ifNoneMatch(metadata.etag) else {
            return Response(status: .notModified, headers: headers)
        }

        return Response(
            status: .ok,
            headers: headers,
            body: .init(data: Data(metadata.bytes))
        )
    }
    
}

extension HTTPHeaders {

    fileprivate func ifNoneMatch(_ etag: String) -> Bool {
        let expected = weakETagValue(etag)

        return self[.ifNoneMatch]
            .flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .contains { value in
                value == "*" || weakETagValue(value) == expected
            }
    }

    private func weakETagValue(_ value: String) -> String {
        value.hasPrefix("W/") ? String(value.dropFirst(2)) : value
    }

}
