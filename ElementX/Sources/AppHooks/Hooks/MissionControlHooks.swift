//
// Mission Control Chat (MIS-103): the white-label configuration. Kept in one file so upstream rebases stay simple.
//

import Compound
import SwiftUI
import UIKit

enum MissionControl {
    static let serverName = "wearemissioncontrol.com"
    /// Matches https://wearemissioncontrol.com/.well-known/matrix/client.
    static let homeserverURL: URL = "https://missionserver.tail2dabe4.ts.net:8443"
    static let website: URL = "https://wearemissioncontrol.com"
    /// Sygnal runs on the homeserver's own machine and only listens on loopback. The pusher URL is called by Tuwunel,
    /// never by the phone, so a loopback address is correct here (same gateway as Rocket Android, MIS-87).
    static let pushGateway: URL = "http://127.0.0.1:5000"

    static let orange = UIColor(red: 1.0, green: 0x4A / 255, blue: 0x1C / 255, alpha: 1)
    static let orangeDeep = UIColor(red: 0xD9 / 255, green: 0x3A / 255, blue: 0x10 / 255, alpha: 1)
    static let orangeSubtle = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x3A / 255, green: 0x1A / 255, blue: 0x10 / 255, alpha: 1)
        : UIColor(red: 1.0, green: 0xE4 / 255, blue: 0xDB / 255, alpha: 1) }
}

struct MissionControlAppSettingsHook: AppSettingsHookProtocol {
    func configure(_ appSettings: AppSettings) -> AppSettings {
        let site = MissionControl.website
        appSettings.override(accountProviders: [.managed(serverName: MissionControl.serverName, baseURL: MissionControl.homeserverURL)],
                             // Pinned: no server picker, and (per the start screen) no Create Account button.
                             allowOtherAccountProviders: false,
                             hideBrandChrome: true,
                             pushGatewayBaseURL: MissionControl.pushGateway,
                             oAuthRedirectURL: site.appending(path: "oauth/ios"),
                             oAuthClientURIPath: nil,
                             websiteURL: site,
                             logoURL: site,
                             copyrightURL: site,
                             acceptableUseURL: site,
                             privacyURL: site,
                             encryptionURL: "https://element.io/help#encryption",
                             deviceVerificationURL: "https://element.io/help#encryption-device-verification",
                             chatBackupDetailsURL: "https://element.io/help#encryption5",
                             identityPinningViolationDetailsURL: "https://element.io/help#encryption18",
                             historySharingDetailsURL: "https://element.io/help#encryption",
                             elementWebHosts: ["chat.wearemissioncontrol.com"],
                             accountProvisioningHost: "chat.wearemissioncontrol.com",
                             bugReportApplicationID: "mc-chat-ios",
                             analyticsTermsURL: nil,
                             mapTilerConfiguration: .init(baseURL: "https://api.maptiler.com/maps", apiKey: nil, lightStyleID: "", darkStyleID: ""))
        return appSettings
    }
}

struct MissionControlCompoundHook: CompoundHookProtocol {
    func override(colors: CompoundColors, uiColors: CompoundUIColors) {
        let accent: [(KeyPath<CompoundColorTokens, Color>, KeyPath<CompoundUIColorTokens, UIColor> & Sendable, UIColor)] = [
            (\.textActionAccent, \.textActionAccent, MissionControl.orange),
            (\.iconAccentPrimary, \.iconAccentPrimary, MissionControl.orange),
            (\.iconAccentTertiary, \.iconAccentTertiary, MissionControl.orange),
            (\.borderAccentPrimary, \.borderAccentPrimary, MissionControl.orange),
            (\.bgAccentRest, \.bgAccentRest, MissionControl.orange),
            (\.bgAccentHovered, \.bgAccentHovered, MissionControl.orangeDeep),
            (\.bgAccentPressed, \.bgAccentPressed, MissionControl.orangeDeep),
            (\.bgAccentSelected, \.bgAccentSelected, MissionControl.orangeSubtle),
            (\.bgAccentSubtle, \.bgAccentSubtle, MissionControl.orangeSubtle),
            (\.bgBadgeAccent, \.bgBadgeAccent, MissionControl.orangeSubtle),
            (\.textBadgeAccent, \.textBadgeAccent, MissionControl.orange),
            (\.borderAccentSubtle, \.borderAccentSubtle, MissionControl.orange)
        ]
        for (swiftUI, uiKit, color) in accent {
            colors.override(swiftUI, with: Color(uiColor: color))
            uiColors.override(uiKit, with: color)
        }
    }
}
