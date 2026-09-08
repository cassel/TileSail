// The Debug ID stays compatible with existing local Accessibility grants.
public let stableAeroSpaceAppId: String = "us.cassel.tilesail"
#if DEBUG
    public let aeroSpaceAppId: String = "bobko.aerospace.debug"
    public let aeroSpaceAppName: String = "TileSail"
#else
    public let aeroSpaceAppId: String = stableAeroSpaceAppId
    public let aeroSpaceAppName: String = "TileSail"
#endif
