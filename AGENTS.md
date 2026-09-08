# TileSail development

- Use the product, display, and executable name `TileSail` in Debug and Release app bundles.
- Preserve the Debug bundle ID `bobko.aerospace.debug` for local Accessibility compatibility. Release uses `us.cassel.tilesail`.
- Keep existing `AeroSpaceSmooth.*` preference keys and TOML configuration paths compatible.
- Install only one active window-manager app. Store backups under `.backups/` as ZIPs or with a non-`.app` extension.
- Update the existing startup agent to the canonical TileSail.app path after migration, preserving its configuration argument.
- Unregister derived build products from Launch Services after installing a build.
- Use author and committer `C. Cassel <c@cassel.us>` for work performed for this maintainer.
- Publish this independent project to `cassel/TileSail`; preserve the complete upstream history and MIT notices.
- Run `swift test` and build the Xcode app before publishing changes that affect the runtime or packaging.
