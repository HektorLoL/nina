import Foundation

protocol RemoteProfileBackend {
    func loadProfile(for user: AuthUser) async throws -> UserProfile?
    func saveProfile(_ profile: UserProfile, user: AuthUser?) async throws
    func loadPhotoData(for userID: String) async throws -> Data
    func savePhotoData(_ data: Data, for userID: String) async throws
    func deletePhoto(for userID: String) async throws
}

#if canImport(Supabase)
import Supabase

struct SupabaseRemoteProfileBackend: RemoteProfileBackend {
    private static let photoBucket = "profile-photos"

    var client: SupabaseClient
    var diagnostics: BackendDiagnosticsStore? = nil

    func loadProfile(for user: AuthUser) async throws -> UserProfile? {
        guard let userID = UUID(uuidString: user.id) else { return nil }

        let rows: [ProfileRow] = try await BackendRequestLogger.perform(
            component: "profile",
            operation: "load",
            diagnostics: diagnostics
        ) {
            try await client
                .from("profiles")
                .select()
                .eq("id", value: userID)
                .limit(1)
                .execute()
                .value
        }

        return rows.first?.domainProfile
    }

    func saveProfile(_ profile: UserProfile, user: AuthUser?) async throws {
        guard let userID = UUID(uuidString: profile.userID) else { return }

        try await BackendRequestLogger.perform(
            component: "profile",
            operation: "save",
            diagnostics: diagnostics
        ) {
            _ = try await client
                .from("profiles")
                .upsert(
                    ProfileUpsertRow(
                        id: userID,
                        displayName: profile.displayName,
                        displayNameSource: "user",
                        email: user?.email,
                        sex: profile.sex.rawValue,
                        householdRole: profile.householdRole.rawValue,
                        phone: profile.phone,
                        birthdayLabel: profile.birthdayLabel,
                        availabilityNote: profile.availabilityNote,
                        communicationPreference: profile.communicationPreference.rawValue,
                        memoryNote: profile.memoryNote,
                        avatar: profile.avatar
                    )
                )
                .execute()
            return ()
        }
    }

    func loadPhotoData(for userID: String) async throws -> Data {
        try await BackendRequestLogger.perform(
            component: "profile_photo",
            operation: "download",
            diagnostics: diagnostics
        ) {
            try await client.storage
                .from(Self.photoBucket)
                .download(path: try photoPath(for: userID))
        }
    }

    func savePhotoData(_ data: Data, for userID: String) async throws {
        let preparedData = try ProfilePhotoPolicy.prepareForStorage(data)

        try await BackendRequestLogger.perform(
            component: "profile_photo",
            operation: "upload",
            diagnostics: diagnostics
        ) {
            _ = try await client.storage
                .from(Self.photoBucket)
                .upload(
                    try photoPath(for: userID),
                    data: preparedData,
                    options: FileOptions(
                        cacheControl: "3600",
                        contentType: "image/jpeg",
                        upsert: true
                    )
                )
            return ()
        }
    }

    func deletePhoto(for userID: String) async throws {
        try await BackendRequestLogger.perform(
            component: "profile_photo",
            operation: "delete",
            diagnostics: diagnostics
        ) {
            _ = try await client.storage
                .from(Self.photoBucket)
                .remove(paths: [try photoPath(for: userID)])
            return ()
        }
    }

    private func photoPath(for userID: String) throws -> String {
        guard UUID(uuidString: userID) != nil else {
            throw RemoteProfileBackendError.invalidUserID
        }

        return "\(userID.lowercased())/avatar.jpg"
    }
}

private enum RemoteProfileBackendError: Error {
    case invalidUserID
}

private struct ProfileRow: Decodable {
    var id: UUID
    var displayName: String
    var sex: String
    var householdRole: String
    var phone: String
    var birthdayLabel: String
    var availabilityNote: String
    var communicationPreference: String
    var memoryNote: String
    var avatar: ProfileAvatar

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case sex
        case householdRole = "household_role"
        case phone
        case birthdayLabel = "birthday_label"
        case availabilityNote = "availability_note"
        case communicationPreference = "communication_preference"
        case memoryNote = "memory_note"
        case avatar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? "Família"
        sex = try container.decodeIfPresent(String.self, forKey: .sex) ?? ProfileSex.notDetermined.rawValue
        householdRole = try container.decodeIfPresent(String.self, forKey: .householdRole) ?? ProfileHouseholdRole.responsibleAdult.rawValue
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        birthdayLabel = try container.decodeIfPresent(String.self, forKey: .birthdayLabel) ?? ""
        availabilityNote = try container.decodeIfPresent(String.self, forKey: .availabilityNote) ?? ""
        communicationPreference = try container.decodeIfPresent(String.self, forKey: .communicationPreference)
            ?? ProfileCommunicationPreference.gentle.rawValue
        memoryNote = try container.decodeIfPresent(String.self, forKey: .memoryNote) ?? ""
        avatar = (try? container.decode(ProfileAvatar.self, forKey: .avatar))?.normalizedPresetVariant() ?? .defaultPreset
    }

    var domainProfile: UserProfile {
        UserProfile(
            userID: id.uuidString,
            displayName: displayName,
            sex: ProfileSex(rawValue: sex) ?? .notDetermined,
            householdRole: ProfileHouseholdRole(rawValue: householdRole) ?? .responsibleAdult,
            phone: phone,
            birthdayLabel: birthdayLabel,
            availabilityNote: availabilityNote,
            communicationPreference: ProfileCommunicationPreference(rawValue: communicationPreference) ?? .gentle,
            memoryNote: memoryNote,
            avatar: avatar.normalizedPresetVariant()
        )
    }
}

private struct ProfileUpsertRow: Encodable {
    var id: UUID
    var displayName: String
    var displayNameSource: String
    var email: String?
    var sex: String
    var householdRole: String
    var phone: String
    var birthdayLabel: String
    var availabilityNote: String
    var communicationPreference: String
    var memoryNote: String
    var avatar: ProfileAvatar

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case displayNameSource = "display_name_source"
        case email
        case sex
        case householdRole = "household_role"
        case phone
        case birthdayLabel = "birthday_label"
        case availabilityNote = "availability_note"
        case communicationPreference = "communication_preference"
        case memoryNote = "memory_note"
        case avatar
    }
}
#endif
