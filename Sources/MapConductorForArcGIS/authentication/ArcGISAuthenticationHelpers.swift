import ArcGIS
import Foundation

private var configuredArcGISApiKey: String?

public func arcGISApiKeyInitialize(apiKey: String) -> Bool {
    NSLog("[MapConductor][ArcGIS] arcGISApiKeyInitialize apiKeyLength=%d", apiKey.count)
    if configuredArcGISApiKey == apiKey {
        NSLog("[MapConductor][ArcGIS] ArcGISEnvironment.apiKey assignment skipped because the same key is already configured")
        return true
    }
    ArcGISEnvironment.apiKey = APIKey(apiKey)
    configuredArcGISApiKey = apiKey
    NSLog("[MapConductor][ArcGIS] ArcGISEnvironment.apiKey assigned")
    return true
}

public func arcGISOAuthApplicationInitialize(
    portalUrl: String,
    clientId: String,
    clientSecret: String,
    tokenExpirationMinutes: Int = 0
) async -> Bool {
    guard let portalURL = URL(string: portalUrl) else { return false }
    ArcGISEnvironment.apiKey = nil
    do {
        let credential = try await OAuthApplicationCredential.credential(
            for: portalURL,
            clientID: clientId,
            clientSecret: clientSecret,
            tokenExpirationMinutes: tokenExpirationMinutes
        )
        _ = try await credential.tokenInfo
        ArcGISEnvironment.authenticationManager.arcGISCredentialStore.add(credential)
        let portal = Portal(url: portalURL, connection: .authenticated)
        try await portal.load()
        return true
    } catch {
        NSLog("[MapConductor] ArcGIS OAuth application authentication failed: %@", String(describing: error))
        return false
    }
}

public func arcGISOAuthUserInitialize(
    portalUrl: String,
    clientId: String,
    redirectUrl: String
) async -> Bool {
    guard let portalURL = URL(string: portalUrl), let redirectURL = URL(string: redirectUrl) else { return false }
    ArcGISEnvironment.apiKey = nil
    do {
        let configuration = OAuthUserConfiguration(
            portalURL: portalURL,
            clientID: clientId,
            redirectURL: redirectURL
        )
        let credential = try await OAuthUserCredential.credential(for: configuration)
        _ = try await credential.tokenInfo
        ArcGISEnvironment.authenticationManager.arcGISCredentialStore.add(credential)
        let portal = Portal(url: portalURL, connection: .authenticated)
        try await portal.load()
        return true
    } catch {
        NSLog("[MapConductor] ArcGIS OAuth user authentication failed: %@", String(describing: error))
        return false
    }
}

public func ArcGISOAuthHybridInitialize(
    portalUrl: String,
    redirectUrl: String,
    clientId: String,
    clientSecret: String? = nil
) async -> Bool {
    if let clientSecret,
       await arcGISOAuthApplicationInitialize(
           portalUrl: portalUrl,
           clientId: clientId,
           clientSecret: clientSecret
       ) {
        return true
    }
    return await arcGISOAuthUserInitialize(
        portalUrl: portalUrl,
        clientId: clientId,
        redirectUrl: redirectUrl
    )
}
