//
//  CloudLibrarySync.swift
//  Omnia
//

import Foundation
import Supabase

/// Typed records for the user-owned tables created by the Omnia Supabase
/// migration. The service intentionally has no access to provider secrets or
/// the server-managed metadata cache.
actor CloudLibrarySync {
    struct LibraryEntry: Codable, Identifiable, Sendable {
        let id: UUID?
        let userID: UUID
        let metadataRecordID: UUID
        let state: State
        let isFavorite: Bool
        let addedAt: Date
        let updatedAt: Date

        enum State: String, Codable, Sendable {
            case saved
            case watching
            case completed
        }

        enum CodingKeys: String, CodingKey {
            case id
            case userID = "user_id"
            case metadataRecordID = "metadata_record_id"
            case state
            case isFavorite = "is_favorite"
            case addedAt = "added_at"
            case updatedAt = "updated_at"
        }
    }

    struct PlaybackProgress: Codable, Identifiable, Sendable {
        let id: UUID?
        let userID: UUID
        let metadataRecordID: UUID
        let episodeKey: String
        let positionSeconds: Double
        let durationSeconds: Double?
        let isCompleted: Bool
        let lastPlayedAt: Date
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case userID = "user_id"
            case metadataRecordID = "metadata_record_id"
            case episodeKey = "episode_key"
            case positionSeconds = "position_seconds"
            case durationSeconds = "duration_seconds"
            case isCompleted = "is_completed"
            case lastPlayedAt = "last_played_at"
            case updatedAt = "updated_at"
        }
    }

    private let client: SupabaseClient

    init(configuration: SupabaseConfiguration) {
        client = SupabaseClient(
            supabaseURL: configuration.projectURL,
            supabaseKey: configuration.publishableKey,
            options: .init(auth: .init(redirectToURL: OmniaAccount.redirectURL, flowType: .pkce))
        )
    }

    func fetchLibrary(for userID: UUID) async throws -> [LibraryEntry] {
        try await client
            .from("library_entries")
            .select()
            .eq("user_id", value: userID.uuidString)
            .order("updated_at", ascending: false)
            .execute()
            .value
    }

    func upsert(_ entry: LibraryEntry) async throws {
        try await client
            .from("library_entries")
            .upsert(entry, onConflict: "user_id,metadata_record_id", returning: .minimal)
            .execute()
    }

    func fetchProgress(for userID: UUID) async throws -> [PlaybackProgress] {
        try await client
            .from("playback_progress")
            .select()
            .eq("user_id", value: userID.uuidString)
            .order("last_played_at", ascending: false)
            .execute()
            .value
    }

    func upsert(_ progress: PlaybackProgress) async throws {
        try await client
            .from("playback_progress")
            .upsert(progress, onConflict: "user_id,metadata_record_id,episode_key", returning: .minimal)
            .execute()
    }
}
