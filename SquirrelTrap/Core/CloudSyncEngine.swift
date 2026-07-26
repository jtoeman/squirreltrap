import CloudKit
import Foundation

/// Syncs IntentStore across your Macs via CloudKit's private database.
/// Unlike ReminderSyncEngine (a foreign app, deliberately conservative,
/// reduced field scope), this is Squirrel Trap syncing with itself: always
/// bidirectional, carries every field, and deletions fully mirror — CloudKit
/// reports deletions explicitly via its change-token mechanism, so there's
/// no resurrection risk the way there was inferring deletions from EventKit.
/// Triggered by push notifications (near-instant), not polling — see
/// SquirrelTrapApp's registerForRemoteNotifications/didReceiveRemoteNotification.
@MainActor
final class CloudSyncEngine: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var accountStatusDescription = "Checking…"

    private let intentStore: IntentStore
    private let preferences: AppPreferences
    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let recordType = "IntentEntry"
    private let subscriptionID = "squirreltrap-changes"

    init(intentStore: IntentStore, preferences: AppPreferences) {
        self.intentStore = intentStore
        self.preferences = preferences
        container = CKContainer(identifier: "iCloud.com.jtoeman.squirreltrap")
        database = container.privateCloudDatabase
        zoneID = CKRecordZone.ID(zoneName: "IntentEntries", ownerName: CKCurrentUserDefaultName)
    }

    func refreshAccountStatus() {
        container.accountStatus { [weak self] status, _ in
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .available: self.accountStatusDescription = "Signed in"
                case .noAccount: self.accountStatusDescription = "Not signed into iCloud"
                case .restricted: self.accountStatusDescription = "iCloud restricted"
                case .temporarilyUnavailable: self.accountStatusDescription = "Temporarily unavailable"
                default: self.accountStatusDescription = "Unavailable"
                }
            }
        }
    }

    /// Creates the custom zone (needed for reliable change-token delta sync —
    /// the default zone doesn't support it the same way) and the push
    /// subscription once, guarded by a persisted flag.
    private func ensureZoneAndSubscriptionExist() async {
        guard !preferences.hasSetUpCloudSync else { return }

        let zone = CKRecordZone(zoneID: zoneID)
        let zoneOp = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
        let zoneOK = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            zoneOp.modifyRecordZonesResultBlock = { result in
                if case .failure(let error) = result {
                    debugLog("Squirrel Trap DEBUG: [CloudSyncEngine] zone creation failed: \(error)\n")
                }
                continuation.resume(returning: (try? result.get()) != nil)
            }
            database.add(zoneOp)
        }
        guard zoneOK else { return }

        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        let subOp = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: nil)
        let subOK = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            subOp.modifySubscriptionsResultBlock = { result in
                if case .failure(let error) = result {
                    debugLog("Squirrel Trap DEBUG: [CloudSyncEngine] subscription creation failed: \(error)\n")
                }
                continuation.resume(returning: (try? result.get()) != nil)
            }
            database.add(subOp)
        }
        guard subOK else { return }

        preferences.hasSetUpCloudSync = true
        debugLog("Squirrel Trap DEBUG: [CloudSyncEngine] zone + subscription created\n")
    }

    func sync() async {
        guard preferences.iCloudSyncEnabled else { return }
        isSyncing = true
        defer { isSyncing = false }

        await ensureZoneAndSubscriptionExist()
        guard preferences.hasSetUpCloudSync else { return }
        await pull()
        await push()
        preferences.lastCloudSyncAt = Date()
    }

    private func pull() async {
        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        config.previousServerChangeToken = preferences.cloudChangeToken
        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID], configurationsByRecordZoneID: [zoneID: config])

        var changedRecords: [CKRecord] = []
        var deletedIDs: [CKRecord.ID] = []
        var newToken: CKServerChangeToken?

        operation.recordWasChangedBlock = { _, result in
            if case .success(let record) = result {
                changedRecords.append(record)
            }
        }
        operation.recordWithIDWasDeletedBlock = { recordID, _ in
            deletedIDs.append(recordID)
        }
        operation.recordZoneChangeTokensUpdatedBlock = { _, token, _ in
            if let token { newToken = token }
        }
        operation.recordZoneFetchResultBlock = { _, result in
            switch result {
            case .success(let success):
                newToken = success.serverChangeToken
            case .failure(let error):
                debugLog("Squirrel Trap DEBUG: [CloudSyncEngine] zone fetch failed: \(error)\n")
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            operation.fetchRecordZoneChangesResultBlock = { result in
                if case .failure(let error) = result {
                    debugLog("Squirrel Trap DEBUG: [CloudSyncEngine] pull failed: \(error)\n")
                }
                continuation.resume()
            }
            database.add(operation)
        }

        if let newToken {
            preferences.cloudChangeToken = newToken
        }

        let lastSync = preferences.lastCloudSyncAt ?? .distantPast
        for record in changedRecords {
            applyPulledRecord(record, lastSync: lastSync)
        }
        for recordID in deletedIDs {
            if let id = UUID(uuidString: recordID.recordName) {
                intentStore.delete(id: id)
            }
        }
        if !changedRecords.isEmpty || !deletedIDs.isEmpty {
            intentStore.resortPendingBySortRank()
        }
        debugLog("Squirrel Trap DEBUG: [CloudSyncEngine] pulled \(changedRecords.count) changed, \(deletedIDs.count) deleted\n")
    }

    /// Most-recent-wins, same rule as Reminders sync: if the local entry also
    /// changed since the last sync, whichever side changed later keeps its
    /// version — an entry that changed only remotely always applies.
    private func applyPulledRecord(_ record: CKRecord, lastSync: Date) {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return }
        let remoteModified = record.modificationDate ?? lastSync

        if let existing = intentStore.entries.first(where: { $0.id == id }) {
            let localChanged = existing.lastModifiedAt > lastSync
            if localChanged, existing.lastModifiedAt >= remoteModified {
                return
            }
        }

        let entry = IntentEntry(
            id: id,
            text: record["text"] as? String ?? "",
            createdAt: record["createdAt"] as? Date ?? Date(),
            completed: record["completed"] as? Bool ?? false,
            completedAt: record["completedAt"] as? Date,
            favorite: record["favorite"] as? Bool ?? false,
            reminderDate: record["reminderDate"] as? Date,
            lastModifiedAt: remoteModified,
            sortRank: record["sortRank"] as? Double ?? 0
        )
        intentStore.applyCloudEntry(entry)
    }

    /// Local changes flow out: anything modified since the last sync gets
    /// saved (savePolicy .allKeys so a freshly constructed CKRecord — no
    /// fetch-before-write round trip — always wins, consistent with our own
    /// app-level "most recent wins" policy), and any local deletion still
    /// owed to the cloud gets sent as a real record deletion.
    private func push() async {
        let lastSync = preferences.lastCloudSyncAt ?? .distantPast
        let toSave = intentStore.entries
            .filter { $0.lastModifiedAt > lastSync }
            .map(makeRecord)
        let deletionIDs = intentStore.pendingCloudDeletionIDs
        let toDelete = deletionIDs.map { CKRecord.ID(recordName: $0.uuidString, zoneID: zoneID) }

        guard !toSave.isEmpty || !toDelete.isEmpty else { return }

        let operation = CKModifyRecordsOperation(recordsToSave: toSave, recordIDsToDelete: toDelete)
        operation.savePolicy = .allKeys

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            operation.modifyRecordsResultBlock = { result in
                if case .failure(let error) = result {
                    debugLog("Squirrel Trap DEBUG: [CloudSyncEngine] push failed: \(error)\n")
                }
                continuation.resume()
            }
            database.add(operation)
        }

        if !toDelete.isEmpty {
            intentStore.clearPendingCloudDeletions(deletionIDs)
        }
        debugLog("Squirrel Trap DEBUG: [CloudSyncEngine] pushed \(toSave.count) saved, \(toDelete.count) deleted\n")
    }

    private func makeRecord(for entry: IntentEntry) -> CKRecord {
        let recordID = CKRecord.ID(recordName: entry.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["text"] = entry.text as CKRecordValue
        record["createdAt"] = entry.createdAt as CKRecordValue
        record["completed"] = entry.completed as CKRecordValue
        record["completedAt"] = entry.completedAt as CKRecordValue?
        record["favorite"] = entry.favorite as CKRecordValue
        record["reminderDate"] = entry.reminderDate as CKRecordValue?
        record["sortRank"] = entry.sortRank as CKRecordValue
        return record
    }
}
