import Foundation

public struct Datapackage: Codable, Sendable {
    public var profile: String = "data-package"
    public var wacz_version: String = waczVersion
    public var software: String = waczSoftware
    public var created: String = nowISO()
    public var resources: [DatapackageResource] = []

    // Optional metadata
    public var title: String?
    public var description: String?
    public var mainPageURL: String?
    public var mainPageDate: String?

    public init() {}

    enum CodingKeys: String, CodingKey {
        case profile, resources, title, description
        case mainPageURL = "mainPageUrl"
        case mainPageDate, created, wacz_version, software
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profile, forKey: .profile)
        try container.encode(wacz_version, forKey: .wacz_version)
        try container.encode(software, forKey: .software)
        try container.encode(created, forKey: .created)
        try container.encode(resources, forKey: .resources)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(mainPageURL, forKey: .mainPageURL)
        try container.encodeIfPresent(mainPageDate, forKey: .mainPageDate)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decodeIfPresent(String.self, forKey: .profile) ?? "data-package"
        wacz_version = try container.decodeIfPresent(String.self, forKey: .wacz_version) ?? waczVersion
        software = try container.decodeIfPresent(String.self, forKey: .software) ?? ""
        created = try container.decodeIfPresent(String.self, forKey: .created) ?? ""
        resources = try container.decodeIfPresent([DatapackageResource].self, forKey: .resources) ?? []
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        mainPageURL = try container.decodeIfPresent(String.self, forKey: .mainPageURL)
        mainPageDate = try container.decodeIfPresent(String.self, forKey: .mainPageDate)
    }
}
