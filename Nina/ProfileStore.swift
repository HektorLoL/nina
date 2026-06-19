import Foundation
import ImageIO
import Observation
#if canImport(UIKit)
import UIKit
#endif

enum ProfilePhotoPolicy {
    static let maxPixelDimension = 512
    static let maxBytes = 350 * 1_024

    static var limitDescription: String {
        "até \(maxPixelDimension) px e \(formattedMaxBytes)"
    }

    static func prepareForStorage(_ data: Data) throws -> Data {
        #if canImport(UIKit)
        guard let imageSource = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw ProfilePhotoError.unreadable
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as NSDictionary?
        let sourceWidth = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let sourceHeight = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw ProfilePhotoError.unreadable
        }

        if data.count <= maxBytes,
           max(sourceWidth, sourceHeight) <= maxPixelDimension,
           data.isJPEG {
            return data
        }

        var targetMaxSide = CGFloat(maxPixelDimension)
        let compressionQualities: [CGFloat] = [0.82, 0.72, 0.62, 0.52, 0.42]

        while targetMaxSide >= 192 {
            let resizedImage = try thumbnailImage(
                from: imageSource,
                maxSide: Int(targetMaxSide.rounded())
            )

            for quality in compressionQualities {
                guard let jpegData = resizedImage.jpegData(compressionQuality: quality) else {
                    throw ProfilePhotoError.unreadable
                }

                if jpegData.count <= maxBytes {
                    return jpegData
                }
            }

            targetMaxSide *= 0.8
        }

        throw ProfilePhotoError.cannotMeetSizeLimit
        #else
        guard data.count <= maxBytes else {
            throw ProfilePhotoError.cannotMeetSizeLimit
        }
        return data
        #endif
    }

    #if canImport(UIKit)
    private static func thumbnailImage(
        from imageSource: CGImageSource,
        maxSide: Int
    ) throws -> UIImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            imageSource,
            0,
            options as CFDictionary
        ) else {
            throw ProfilePhotoError.unreadable
        }

        let targetSize = CGSize(width: thumbnail.width, height: thumbnail.height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            UIImage(cgImage: thumbnail).draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    #endif

    private static var formattedMaxBytes: String {
        ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file)
    }
}

enum ProfilePhotoError: LocalizedError {
    case unreadable
    case cannotMeetSizeLimit

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "Essa imagem não pôde ser lida. Escolha outra foto."
        case .cannotMeetSizeLimit:
            "Não foi possível reduzir a foto para \(ProfilePhotoPolicy.limitDescription)."
        }
    }
}

#if canImport(UIKit)
private extension Data {
    var isJPEG: Bool {
        count >= 3 && self[startIndex] == 0xFF && self[index(after: startIndex)] == 0xD8
    }
}
#endif

enum ProfileHouseholdRole: String, CaseIterable, Codable, Hashable, Identifiable {
    case responsibleAdult
    case partner
    case parent
    case familyMember
    case roommate
    case caregiver

    var id: String { rawValue }

    var title: String {
        switch self {
        case .responsibleAdult: "Responsável"
        case .partner: "Parceiro(a)"
        case .parent: "Mãe/Pai"
        case .familyMember: "Familiar"
        case .roommate: "Morador(a)"
        case .caregiver: "Cuidador(a)"
        }
    }

    var symbolName: String {
        switch self {
        case .responsibleAdult: "person.fill.checkmark"
        case .partner: "heart.fill"
        case .parent: "figure.2.and.child.holdinghands"
        case .familyMember: "person.2.fill"
        case .roommate: "house.fill"
        case .caregiver: "cross.case.fill"
        }
    }
}

enum ProfileSex: String, CaseIterable, Codable, Hashable, Identifiable {
    case masculine
    case feminine
    case notDetermined

    var id: String { rawValue }

    var title: String {
        switch self {
        case .masculine: "Masculino"
        case .feminine: "Feminino"
        case .notDetermined: "Não determinado"
        }
    }

    var symbolName: String {
        switch self {
        case .masculine, .feminine: "person.fill"
        case .notDetermined: "questionmark.circle.fill"
        }
    }

    static func fromLegacyPronouns(_ label: String?) -> ProfileSex {
        let normalized = label?
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let hasEla = normalized.contains("ela")
        let hasEle = normalized.contains("ele")

        if hasEla && !hasEle { return .feminine }
        if hasEle && !hasEla { return .masculine }
        return .notDetermined
    }
}

enum ProfileCommunicationPreference: String, CaseIterable, Codable, Hashable, Identifiable {
    case direct
    case gentle
    case detailed
    case brief

    var id: String { rawValue }

    var title: String {
        switch self {
        case .direct: "Direta"
        case .gentle: "Com calma"
        case .detailed: "Com contexto"
        case .brief: "Bem curta"
        }
    }

    var detail: String {
        switch self {
        case .direct: "Mostre o próximo passo sem rodeio."
        case .gentle: "Sugira com um tom mais cuidadoso."
        case .detailed: "Explique o porquê da sugestão."
        case .brief: "Poucas palavras e ações claras."
        }
    }
}

enum ProfileAvatarKind: String, Codable, Hashable {
    case preset
    case photo
}

struct ProfileAvatar: Codable, Hashable {
    var kind: ProfileAvatarKind
    var symbolName: String
    var tone: MemberTone
    var photoID: String?

    static let defaultPreset = ProfileAvatar(
        kind: .preset,
        symbolName: "avatar.base",
        tone: .mint,
        photoID: nil
    )

    var presetID: String {
        "\(symbolName)-\(tone.rawValue)"
    }

    func asPhoto(for userID: String) -> ProfileAvatar {
        ProfileAvatar(
            kind: .photo,
            symbolName: symbolName,
            tone: tone,
            photoID: "photo-\(userID)"
        )
    }

    func normalizedPresetVariant() -> ProfileAvatar {
        guard kind == .preset else { return self }

        switch symbolName {
        case "person.fill":
            return ProfileAvatar(kind: kind, symbolName: "avatar.base", tone: .mint, photoID: photoID)
        case "heart.fill":
            return ProfileAvatar(kind: kind, symbolName: "avatar.shortHair", tone: .coral, photoID: photoID)
        case "house.fill":
            return ProfileAvatar(kind: kind, symbolName: "avatar.longHair", tone: .sky, photoID: photoID)
        case "sparkles":
            return ProfileAvatar(kind: kind, symbolName: "avatar.bangs", tone: .lavender, photoID: photoID)
        case "book.closed.fill":
            return ProfileAvatar(kind: kind, symbolName: "avatar.glasses", tone: .amber, photoID: photoID)
        case "leaf.fill":
            return ProfileAvatar(kind: kind, symbolName: "avatar.smile", tone: .mint, photoID: photoID)
        case "briefcase.fill":
            return ProfileAvatar(kind: kind, symbolName: "avatar.collar", tone: .sky, photoID: photoID)
        case "moon.fill":
            return ProfileAvatar(kind: kind, symbolName: "avatar.soft", tone: .lavender, photoID: photoID)
        default:
            return symbolName.hasPrefix("avatar.") ? self : ProfileAvatar(kind: kind, symbolName: "avatar.base", tone: tone, photoID: photoID)
        }
    }
}

struct ProfileAvatarPreset: Identifiable, Hashable {
    var id: String
    var title: String
    var symbolName: String
    var tone: MemberTone

    var avatar: ProfileAvatar {
        ProfileAvatar(kind: .preset, symbolName: symbolName, tone: tone, photoID: nil)
    }

    static let all: [ProfileAvatarPreset] = [
        ProfileAvatarPreset(id: "avatar.base-mint", title: "Base", symbolName: "avatar.base", tone: .mint),
        ProfileAvatarPreset(id: "avatar.shortHair-coral", title: "Curto", symbolName: "avatar.shortHair", tone: .coral),
        ProfileAvatarPreset(id: "avatar.longHair-sky", title: "Longo", symbolName: "avatar.longHair", tone: .sky),
        ProfileAvatarPreset(id: "avatar.bangs-lavender", title: "Franja", symbolName: "avatar.bangs", tone: .lavender),
        ProfileAvatarPreset(id: "avatar.glasses-amber", title: "Óculos", symbolName: "avatar.glasses", tone: .amber),
        ProfileAvatarPreset(id: "avatar.smile-mint", title: "Sorriso", symbolName: "avatar.smile", tone: .mint),
        ProfileAvatarPreset(id: "avatar.collar-sky", title: "Gola", symbolName: "avatar.collar", tone: .sky),
        ProfileAvatarPreset(id: "avatar.soft-lavender", title: "Suave", symbolName: "avatar.soft", tone: .lavender)
    ]
}

struct UserProfile: Codable, Hashable, Identifiable {
    var id: String { userID }

    var userID: String
    var displayName: String
    var sex: ProfileSex
    var householdRole: ProfileHouseholdRole
    var phone: String
    var birthdayLabel: String
    var availabilityNote: String
    var communicationPreference: ProfileCommunicationPreference
    var memoryNote: String
    var avatar: ProfileAvatar

    init(
        userID: String,
        displayName: String,
        sex: ProfileSex,
        householdRole: ProfileHouseholdRole,
        phone: String,
        birthdayLabel: String,
        availabilityNote: String,
        communicationPreference: ProfileCommunicationPreference,
        memoryNote: String,
        avatar: ProfileAvatar
    ) {
        self.userID = userID
        self.displayName = displayName
        self.sex = sex
        self.householdRole = householdRole
        self.phone = phone
        self.birthdayLabel = birthdayLabel
        self.availabilityNote = availabilityNote
        self.communicationPreference = communicationPreference
        self.memoryNote = memoryNote
        self.avatar = avatar
    }

    static func `default`(for user: AuthUser) -> UserProfile {
        UserProfile(
            userID: user.id,
            displayName: user.displayName,
            sex: .notDetermined,
            householdRole: .responsibleAdult,
            phone: "",
            birthdayLabel: "",
            availabilityNote: "Costuma resolver coisas da casa no fim do dia.",
            communicationPreference: .gentle,
            memoryNote: "Prefere lembretes práticos e sem pressão.",
            avatar: .defaultPreset
        )
    }

    private enum CodingKeys: String, CodingKey {
        case userID
        case displayName
        case sex
        case pronounsLabel
        case householdRole
        case phone
        case birthdayLabel
        case availabilityNote
        case communicationPreference
        case memoryNote
        case avatar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        userID = try container.decode(String.self, forKey: .userID)
        displayName = try container.decode(String.self, forKey: .displayName)
        sex = try container.decodeIfPresent(ProfileSex.self, forKey: .sex)
            ?? ProfileSex.fromLegacyPronouns(try container.decodeIfPresent(String.self, forKey: .pronounsLabel))
        householdRole = try container.decode(ProfileHouseholdRole.self, forKey: .householdRole)
        phone = try container.decode(String.self, forKey: .phone)
        birthdayLabel = try container.decode(String.self, forKey: .birthdayLabel)
        availabilityNote = try container.decode(String.self, forKey: .availabilityNote)
        communicationPreference = try container.decode(ProfileCommunicationPreference.self, forKey: .communicationPreference)
        memoryNote = try container.decode(String.self, forKey: .memoryNote)
        avatar = try container.decode(ProfileAvatar.self, forKey: .avatar).normalizedPresetVariant()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(userID, forKey: .userID)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(sex, forKey: .sex)
        try container.encode(householdRole, forKey: .householdRole)
        try container.encode(phone, forKey: .phone)
        try container.encode(birthdayLabel, forKey: .birthdayLabel)
        try container.encode(availabilityNote, forKey: .availabilityNote)
        try container.encode(communicationPreference, forKey: .communicationPreference)
        try container.encode(memoryNote, forKey: .memoryNote)
        try container.encode(avatar, forKey: .avatar)
    }
}

@MainActor
@Observable
final class ProfileStore {
    var profiles: [String: UserProfile] = [:]
    var photoVersions: [String: Int] = [:]

    @ObservationIgnored private var defaults: UserDefaults
    @ObservationIgnored private let remoteProfileBackend: (any RemoteProfileBackend)?

    init(
        defaults: UserDefaults = .standard,
        remoteProfileBackend: (any RemoteProfileBackend)? = BackendServices.makeRemoteProfileBackend()
    ) {
        self.defaults = defaults
        self.remoteProfileBackend = remoteProfileBackend
    }

    func profile(for user: AuthUser) -> UserProfile {
        if let profile = profiles[user.id] {
            return profile
        }

        let profile = loadProfile(for: user.id) ?? UserProfile.default(for: user)
        profiles[user.id] = profile
        return profile
    }

    func refreshProfile(for user: AuthUser?) async {
        guard let user else { return }

        #if DEBUG
        if user.isDebugAccount {
            _ = profile(for: user)
            return
        }
        #endif

        guard let remoteProfileBackend else { return }

        do {
            if let remoteProfile = try await remoteProfileBackend.loadProfile(for: user) {
                profiles[user.id] = remoteProfile
                persistProfileLocally(remoteProfile)

                if remoteProfile.avatar.kind == .photo {
                    do {
                        let downloadedData = try await remoteProfileBackend.loadPhotoData(for: user.id)
                        let photoData = try ProfilePhotoPolicy.prepareForStorage(downloadedData)
                        defaults.set(photoData, forKey: Self.photoKey(for: user.id))
                        photoVersions[user.id, default: 0] += 1

                        if photoData != downloadedData {
                            try? await remoteProfileBackend.savePhotoData(photoData, for: user.id)
                        }
                    } catch {
                        if let cachedPhoto = defaults.data(forKey: Self.photoKey(for: user.id)),
                           let preparedPhoto = try? ProfilePhotoPolicy.prepareForStorage(cachedPhoto) {
                            defaults.set(preparedPhoto, forKey: Self.photoKey(for: user.id))
                            try? await remoteProfileBackend.savePhotoData(preparedPhoto, for: user.id)
                        }
                    }
                } else {
                    defaults.removeObject(forKey: Self.photoKey(for: user.id))
                    photoVersions[user.id, default: 0] += 1
                }
            } else {
                let localProfile = profile(for: user)
                try await remoteProfileBackend.saveProfile(localProfile, user: user)

                if localProfile.avatar.kind == .photo,
                   let cachedPhoto = defaults.data(forKey: Self.photoKey(for: user.id)),
                   let preparedPhoto = try? ProfilePhotoPolicy.prepareForStorage(cachedPhoto) {
                    defaults.set(preparedPhoto, forKey: Self.photoKey(for: user.id))
                    try? await remoteProfileBackend.savePhotoData(preparedPhoto, for: user.id)
                }
            }
        } catch {
            return
        }
    }

    func saveProfile(_ profile: UserProfile, user: AuthUser? = nil) {
        profiles[profile.userID] = profile
        persistProfileLocally(profile)

        guard !AuthUser.isDebugAccountID(profile.userID) else { return }

        if let remoteProfileBackend {
            Task {
                try? await remoteProfileBackend.saveProfile(profile, user: user)
            }
        }
    }

    func savePhotoData(_ data: Data, for userID: String) throws {
        let preparedData = try ProfilePhotoPolicy.prepareForStorage(data)
        defaults.set(preparedData, forKey: Self.photoKey(for: userID))
        photoVersions[userID, default: 0] += 1

        guard !AuthUser.isDebugAccountID(userID) else { return }

        if let remoteProfileBackend {
            Task {
                try? await remoteProfileBackend.savePhotoData(preparedData, for: userID)
            }
        }
    }

    func photoData(for profile: UserProfile) -> Data? {
        guard profile.avatar.kind == .photo else { return nil }
        _ = photoVersions[profile.userID, default: 0]
        return defaults.data(forKey: Self.photoKey(for: profile.userID))
    }

    func deleteLocalPhoto(for userID: String) {
        defaults.removeObject(forKey: Self.photoKey(for: userID))
        photoVersions[userID, default: 0] += 1

        guard !AuthUser.isDebugAccountID(userID) else { return }

        if let remoteProfileBackend {
            Task {
                try? await remoteProfileBackend.deletePhoto(for: userID)
            }
        }
    }

    private func loadProfile(for userID: String) -> UserProfile? {
        guard let data = defaults.data(forKey: Self.profileKey(for: userID)) else { return nil }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }

    private func persistProfileLocally(_ profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: Self.profileKey(for: profile.userID))
    }

    private static func profileKey(for userID: String) -> String {
        "nina.profile.metadata.\(userID)"
    }

    private static func photoKey(for userID: String) -> String {
        "nina.profile.photo.\(userID)"
    }
}
