import AppKit
import Common

@MainActor
func showTileSailAboutPanel() {
    let credits = NSMutableAttributedString(string: "")
    let body: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        .foregroundColor: NSColor.labelColor,
    ]
    credits.append(NSAttributedString(
        string: "Created and maintained by Cleverson Cassel (C. Cassel).\nFounder and CEO of CambioReal.\n\nAn independent macOS window manager focused on fast, practical window management and multi-monitor workflows.\n\n",
        attributes: body,
    ))
    for (title, address) in [
        ("Project and source code", "https://github.com/cassel/TileSail"),
        ("Downloads and release notes", "https://github.com/cassel/TileSail/releases"),
        ("Report an issue", "https://github.com/cassel/TileSail/issues"),
        ("Contact C. Cassel", "mailto:c@cassel.us"),
    ] {
        var attributes = body
        attributes[.link] = URL(string: address)
        credits.append(NSAttributedString(string: title, attributes: attributes))
        credits.append(NSAttributedString(string: "\n", attributes: body))
    }
    credits.append(NSAttributedString(
        string: "\nDerived from AeroSpace by Nikita Bobko and contributors. Continues the AeroSpaceSmooth development line.\n\nReleased under the MIT license. Original copyrights and third-party notices are preserved.\n\nTileSail is independently maintained and is not an official AeroSpace release.",
        attributes: body,
    ))
    NSApplication.shared.orderFrontStandardAboutPanel(options: [
        .applicationName: "TileSail",
        .applicationVersion: aeroSpaceAppVersion,
        .version: gitShortHash,
        .credits: credits,
    ])
    NSApplication.shared.activate(ignoringOtherApps: true)
}
