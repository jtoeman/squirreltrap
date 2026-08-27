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
    /// Set whenever the most recent sync() attempt hit a real error (pull or
    /// push), cleared at the start of every new attempt. Surfaced in
    /// PreferencesSyncTab so a failed sync is visibly distinguishable from a
    /// successful one, rather than both silently reverting to the same
    /// resting Sync Now button with no feedback either way.
    @Published private(set) var lastSyncError: String?
    /// A quick human-readable summary of what the most recent successful
    /// pull actually brought in -- e.g. "2 added, 1 completed" -- so syncing
    /// isn't a black box. Deliberately reports only the pull (incoming) side:
    /// what you just pushed out is whatever you did yourself moments ago in
    /// this same UI, so echoing it back adds noise, not information. Cleared
    /// at the start of every sync() attempt.
    @Published private(set) var lastSyncSummary: String?

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
    /// the default zone doesn't support it the same way), guarded by a
    /// persisted flag. Actual pull/push depends only on this succeeding.
    @discardableResult
    private func ensureZoneExists() async -> Bool {
        guard !preferences.hasSetUpCloudSync else { return true }

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
        if zoneOK {
            preferences.hasSetUpCloudSync = true
            debugLog("Squirrel Trap DEBUG: [CloudSyncEngine] zone created\n")
        }
        return zoneOK
    }

    /// Creates the push subscription, guarded by its own persisted flag,
    /// entirely separate from the zone flag above. This only enables
    /// near-instant push-triggered sync -- a failure here must never block
    /// actual data sync (pull/push only need the zone), so this is best
    /// effort and retried on the next sync() call if it fails.
    private func ensureSubscriptionExists() async {
        guard !preferences.hasCreatedCloudSubscription else { return }

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
        if subOK {
            preferences.hasCreatedCloudSubscription = true
            debugLog("Squirrel Trap DEBUG: [CloudSyncEngine] subscription created\n")
        }
    }

    func sync() async {
        guard preferences.iCloudSyncEnabled else { return }
        isSyncing = true
        lastSyncError = nil
        lastSyncSummary = nil
        defer { isSyncing = false }

        guard await ensureZoneExists() else {
            lastSyncError = "Couldn't set up iCloud sync. Check your iCloud sign-in and try again."
            return
        }
        await ensureSubscriptionExists()
        let pullResult = await pull()
        let sentCount = await push()

        var summaryParts: [String] = []
        if sentCount > 0 { summaryParts.append("\(sentCount) sent") }
        if pullResult.added > 0 { summaryParts.append("\(pullResult.added) added") }
        if pullResult.completed > 0 { summaryParts.append("\(pullResult.completed) completed") }
        if pullResult.removed > 0 { summaryParts.append("\(pullResult.removed) removed") }
        lastSyncSummary = summaryParts.isEmpty ? "No changes" : summaryParts.joined(separator: ", ")
    }

    private struct PullResult {
        var added = 0
        var completed = 0
        var removed = 0
    }

    @discardableResult
    private func pull() async -> PullResult {
        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        config.previousServerChangeToken = preferences.cloudChangeToken
        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID], configurationsByRecordZoneID: [zoneID: config])
        // Root-caused 2026-08-26: macOS Low Power Mode throttles CloudKit's
        // background data task indefinitely -- no error, no completion, ever,
        // until Low Power Mode is turned off (confirmed: same operation
        // completes in ~3s with it off). Without a bound, that leaves the
        // Sync Now spinner running forever with no feedback at all. This
        // timeout can't fix the throttling, but it guarantees a completion
        // (which becomes a real, user-visible error via lastSyncError below)
        // instead of an indistinguishable-from-frozen silence.
        operation.configuration.timeoutIntervalForRequest = 45
        operation.configuration.timeoutIntervalForResource = 60

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
        operation.recordZoneFetchResultBlock = { [weak self] _, result in
            switch result {
            case .success(let success):
                newToken = success.serverChangeToken
            case .failure(let error):
                debugLog("Squirrel Trap DEBUG: [CloudSyncEngine] zone fetch failed: \(error)\n")
                // CloudKit invalidates a saved change token after enough
                // dormancy (or a schema change) and there is no way to
                // recover a delta fetch once that happens -- every future
                // sync would otherwise fail this exact way forever, leaving
                // this device permanently, silently stale: never learning
                // about edits or deletions made on any other device. This
                // never destroys anything locally, but a device that's
                // stopped hearing about the rest of the world is exactly
                // the kind of silent failure this audit is meant to catch.
                // Clearing the token trades one heavier full re-fetch next
                // sync for actually recovering.
                if let ckError = error as? CKError, ckError.code == .changeTokenExpired {
                    self?.preferences.cloudChangeToken = nil
                    debugLog("Squirrel Trap DEBUG: [CloudSyncEngine] change token expired -- cleared for a full re-fetch next sync\n")
                }
            }
        }

        var pullError: Error?
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            operation.fetchRecordZoneChangesResultBlock = { result in
                if case .failure(let error) = result {
                    debugLog("Squirrel Trap DEBUG: [CloudSyncEngine] pull failed: \(error)\n")
                    pullError = error
                }
                continuation.resume()
            }
            database.add(operation)
        }

        if let pullError {
            lastSyncError = "iCloud sync couldn't check for changes: \(pullError.localizedDescription)"
        }

        if let newToken {
            preferences.cloudChangeToken = newToken
        }

        let lastSync = preferences.lastCloudSyncAt ?? .distantPast
        var addedCount = 0
        var completedCount = 0
        for record in changedRecords {
            switch applyPulledRecord(record, lastSync: lastSync) {
            case .added: addedCount += 1
            case .completedNewly: completedCount += 1
            case .updatedOther, .skipped: break
            }
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
        return PullResult(added: addedCount, completed: completedCount, removed: deletedIDs.count)
    }

    private enum PullOutcome {
        /// A genuinely new entry, not previously known on this device.
        case added
        /// An existing entry whose completed flag flipped false -> true
        /// because of this pull specifically -- the one other-worthy-of-a-
        /// mention transition (vs. a bare edit, favorite toggle, reorder,
        /// etc., which just fold into "updated" and aren't called out).
        case completedNewly
        case updatedOther
        /// Local won the conflict (see the doc comment below) -- nothing
        /// was actually applied, so it must not count toward the summary.
        case skipped
    }

    /// Most-recent-wins, same rule as Reminders sync: if the local entry also
    /// changed since the last sync, whichever side changed later keeps its
    /// version — an entry that changed only remotely always applies.
    @discardableResult
    private func applyPulledRecord(_ record: CKRecord, lastSync: Date) -> PullOutcome {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return .skipped }
        let remoteModified = record.modificationDate ?? lastSync
        let remoteCompleted = record["completed"] as? Bool ?? false

        let existing = intentStore.entries.first(where: { $0.id == id })
        if let existing {
            let localChanged = existing.lastModifiedAt > lastSync
            if localChanged, existing.lastModifiedAt >= remoteModified {
                return .skipped
            }
        }

        let entry = IntentEntry(
            id: id,
            text: record["text"] as? String ?? "",
            createdAt: record["createdAt"] as? Date ?? Date(),
            completed: remoteCompleted,
            completedAt: record["completedAt"] as? Date,
            favorite: record["favorite"] as? Bool ?? false,
            reminderDate: record["reminderDate"] as? Date,
            lastModifiedAt: remoteModified,
            sortRank: record["sortRank"] as? Double ?? 0,
            colorTag: TodoColorTag(rawValue: record["colorTag"] as? String ?? ""),
            sourceAppName: record["sourceAppName"] as? String,
            sourceAppBundleID: record["sourceAppBundleID"] as? String
        )
        intentStore.applyCloudEntry(entry)

        guard let existing else { return .added }
        return (!existing.completed && remoteCompleted) ? .completedNewly : .updatedOther
    }

    /// Local changes flow out: anything modified since the last *successful*
    /// push gets saved (savePolicy .allKeys so a freshly constructed CKRecord
    /// — no fetch-before-write round trip — always wins, consistent with our
    /// own app-level "most recent wins" policy), and any local deletion still
    /// owed to the cloud gets sent as a real record deletion.
    ///
    /// lastCloudSyncAt only advances here, and only when the push actually
    /// succeeds (or there was nothing to push) — it's also this function's
    /// own filter threshold for "what's changed since last time." Previously
    /// sync() advanced it unconditionally after awaiting push(), so a single
    /// failed CKModifyRecordsOperation (network blip, iCloud hiccup, no
    /// matter how transient) silently and *permanently* excluded every item
    /// in that batch from ever being retried, since their lastModifiedAt was
    /// now stuck behind an already-advanced timestamp.
    /// Returns how many entries were actually sent (0 if there was nothing to
    /// push, or if the push failed) -- rolled into the sync report alongside
    /// pull()'s tally.
    @discardableResult
    private func push() async -> Int {
        let lastSync = preferences.lastCloudSyncAt ?? .distantPast
        let toSave = intentStore.entries
            .filter { $0.lastModifiedAt > lastSync }
            .map(makeRecord)
        let deletionIDs = intentStore.pendingCloudDeletionIDs
        let toDelete = deletionIDs.map { CKRecord.ID(recordName: $0.uuidString, zoneID: zoneID) }

        guard !toSave.isEmpty || !toDelete.isEmpty else {
            preferences.lastCloudSyncAt = Date()
            return 0
        }

        let operation = CKModifyRecordsOperation(recordsToSave: toSave, recordIDsToDelete: toDelete)
        operation.savePolicy = .allKeys

        var pushError: Error?
        let succeeded = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            operation.modifyRecordsResultBlock = { result in
                if case .failure(let error) = result {
                    debugLog("Squirrel Trap DEBUG: [CloudSyncEngine] push failed: \(error)\n")
                    pushError = error
                }
                continuation.resume(returning: (try? result.get()) != nil)
            }
            database.add(operation)
        }

        if succeeded {
            if !toDelete.isEmpty {
                intentStore.clearPendingCloudDeletions(deletionIDs)
            }
            preferences.lastCloudSyncAt = Date()
        } else if let pushError {
            lastSyncError = "iCloud sync couldn't save your changes: \(pushError.localizedDescription)"
        }
        debugLog("Squirrel Trap DEBUG: [CloudSyncEngine] pushed \(toSave.count) saved, \(toDelete.count) deleted, succeeded=\(succeeded)\n")
        return succeeded ? toSave.count : 0
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
        record["colorTag"] = entry.colorTag?.rawValue as CKRecordValue?
        record["sourceAppName"] = entry.sourceAppName as CKRecordValue?
        record["sourceAppBundleID"] = entry.sourceAppBundleID as CKRecordValue?
        return record
    }
}
