import Foundation
import SwiftData
import WidgetKit
import CubbyCore
import os

/// The one place entries are created and changed. Views, intents and notifications all go
/// through here, so classification, reminders and the widget stay in step.
@MainActor
final class CubbyModel {
    static let shared = CubbyModel()

    let container: ModelContainer
    let notifications = NotificationService()

    private let pipeline = ClassificationPipeline()
    private let log = Logger(subsystem: "Cubby", category: "model")
    private var refining = Set<UUID>()
    private var fetchingLinks = Set<UUID>()
    private var isRunningBacklog = false
    private var refreshTask: Task<Void, Never>?

    /// How many older entries the language model revisits per app launch or refresh.
    static let backlogBatch = 40

    var context: ModelContext {
        container.mainContext
    }

    private init() {
        AppSettings.registerDefaults()
        container = CubbyStore.makeContainer()
        notifications.onMarkDone = { [weak self] id in
            self?.markDone(id: id)
        }
        notifications.onOpen = { destination in
            if let url = URL(string: "cubby://" + destination) {
                AppRouter.shared.handle(url: url)
            }
        }
        if DemoData.isEnabled {
            DemoData.seed(into: self)
        }
    }

    // MARK: - Capture

    /// Saves an entry immediately with the instant classification, then lets the language model
    /// refine it in the background. Capture never waits on a model.
    @discardableResult
    func capture(_ rawText: String, source: CaptureSource, createdAt: Date = Date()) -> Entry? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let entry = Entry(text: text, source: source, createdAt: createdAt)
        entry.apply(pipeline.quick(text: text, capturedAt: createdAt), version: ClassificationPipeline.version)
        context.insert(entry)
        save()

        syncReminder(for: entry)
        refine(entry)
        fetchLinkTitle(for: entry)
        refreshDerived()
        return entry
    }

    /// Brings in anything the share extension left in the shared inbox.
    func importInbox() {
        guard let queue = InboxQueue.shared else { return }
        for pending in queue.drain() {
            let source = CaptureSource(rawValue: pending.source) ?? .shareExtension
            capture(pending.text, source: source, createdAt: pending.createdAt)
        }
    }

    // MARK: - Corrections and completion

    func toggleDone(_ entry: Entry) {
        entry.completedAt = entry.completedAt == nil ? Date() : nil
        commit(entry)
    }

    /// The user says this is, or is not, a to-do. Their word outranks any classifier.
    func setTodo(_ entry: Entry, _ isTodo: Bool) {
        entry.todoOverride = isTodo
        if isTodo, !entry.deadlineOverridden, entry.inferredDeadline == nil {
            // The classifier drops dates on non-to-dos; look again now that it is one.
            let body = LinkDetector.strippingURLs(from: entry.rawText)
            if let parsed = DeadlineParser().parse(body, reference: entry.createdAt) {
                entry.inferredDeadline = parsed.date
                entry.inferredDeadlineHasTime = parsed.hasTime
            }
        }
        entry.recomputeEffective()
        commit(entry)
    }

    /// Sets or clears the deadline by hand. Giving something a deadline makes it a to-do.
    func setDeadline(_ entry: Entry, date: Date?, hasTime: Bool) {
        entry.deadlineOverridden = true
        entry.deadline = date
        entry.deadlineHasTime = date == nil ? false : hasTime
        if date != nil, !entry.isTodo {
            entry.todoOverride = true
            entry.recomputeEffective()
        }
        commit(entry)
    }

    func delete(_ entry: Entry) {
        let id = entry.id
        context.delete(entry)
        save()
        notifications.cancelDeadline(id: id)
        refreshDerived()
    }

    private func markDone(id: UUID) {
        guard let entry = entry(id: id), entry.isTodo, entry.completedAt == nil else { return }
        entry.completedAt = Date()
        commit(entry)
    }

    private func commit(_ entry: Entry) {
        save()
        syncReminder(for: entry)
        refreshDerived()
    }

    // MARK: - Classification

    /// Asks the on-device model for a better answer, if this device has one.
    private func refine(_ entry: Entry) {
        guard FoundationModelsClassifier.isAvailable else { return }
        Task { [weak self] in
            await self?.refineNow(entry)
        }
    }

    private func refineNow(_ entry: Entry) async {
        guard isLive(entry) else { return }
        let id = entry.id
        guard refining.insert(id).inserted else { return }
        defer { refining.remove(id) }

        let text = entry.rawText
        let capturedAt = entry.createdAt
        do {
            let answer = try await FoundationModelsClassifier().classify(text: text, sentAt: capturedAt)
            guard isLive(entry) else { return }
            entry.apply(pipeline.merge(text: text, capturedAt: capturedAt, llm: answer), version: ClassificationPipeline.version)
        } catch {
            // The instant classification stands. Guardrails, an unsupported language or a busy
            // model all land here.
            log.info("Refinement skipped: \(error.localizedDescription, privacy: .public)")
            guard isLive(entry) else { return }
        }
        entry.refineAttemptVersion = ClassificationPipeline.version
        save()
        syncReminder(for: entry)
        refreshDerived()
    }

    /// Re-runs the rules after an app update and lets the model work through entries it has not
    /// seen, newest first. Pass `limit: nil` to process everything.
    func classifyBacklog(limit: Int? = CubbyModel.backlogBatch) async {
        guard !isRunningBacklog else { return }
        isRunningBacklog = true
        defer { isRunningBacklog = false }

        let descriptor = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let all = (try? context.fetch(descriptor)) ?? []

        var changed = false
        for entry in all where entry.classifierVersion < ClassificationPipeline.version {
            entry.apply(pipeline.quick(text: entry.rawText, capturedAt: entry.createdAt), version: ClassificationPipeline.version)
            syncReminder(for: entry)
            changed = true
        }
        if changed { save() }

        for entry in all where entry.linkTitle == nil && entry.linkFetchAttemptedAt == nil {
            fetchLinkTitle(for: entry)
        }

        guard FoundationModelsClassifier.isAvailable else {
            if changed { refreshDerived() }
            return
        }
        var pending = all.filter { $0.refineAttemptVersion < ClassificationPipeline.version }
        if let limit { pending = Array(pending.prefix(limit)) }
        // One at a time: several model sessions at once would compete for the same hardware.
        for entry in pending {
            await refineNow(entry)
        }
    }

    /// Forgets what the classifiers decided (never the user's corrections) and sorts everything again.
    func resortEverything() async {
        let all = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        for entry in all {
            entry.classifierVersion = 0
            entry.refineAttemptVersion = 0
        }
        save()
        await classifyBacklog(limit: nil)
    }

    // MARK: - Links

    private func fetchLinkTitle(for entry: Entry) {
        guard AppSettings.linkPreviews, entry.linkTitle == nil, entry.linkFetchAttemptedAt == nil,
              let url = entry.urls.first else { return }
        let id = entry.id
        guard fetchingLinks.insert(id).inserted else { return }
        entry.linkFetchAttemptedAt = Date()

        Task { [weak self] in
            let title = await LinkMetadata.title(for: url)
            guard let self else { return }
            self.fetchingLinks.remove(id)
            guard let title, self.isLive(entry) else { return }
            entry.linkTitle = title
            self.save()
        }
    }

    // MARK: - Reminders, widget and digest

    private func syncReminder(for entry: Entry) {
        // Demo data is for looking at; it shouldn't schedule reminders or ask for permission.
        guard !DemoData.isEnabled else { return }
        let id = entry.id
        let title = entry.title
        let deadline = entry.deadline
        let hasTime = entry.deadlineHasTime
        let isOpenTodo = entry.isOpenTodo
        Task {
            await notifications.syncDeadline(id: id, title: title, deadline: deadline, hasTime: hasTime, isOpenTodo: isOpenTodo)
        }
    }

    /// Updates the widget and the weekly digest. Coalesces bursts of changes unless asked not to.
    func refreshDerived(immediately: Bool = false) {
        refreshTask?.cancel()
        if immediately {
            performRefresh()
            return
        }
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.performRefresh()
        }
    }

    private func performRefresh() {
        let all = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        let now = Date()
        let calendar = Calendar.current
        let open = all.filter(\.isOpenTodo)

        let next = open
            .filter { $0.deadline != nil }
            .min { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
        WidgetSnapshot(
            openTodoCount: open.count,
            nextTitle: next?.title,
            nextDeadline: next?.deadline,
            nextDeadlineHasTime: next?.deadlineHasTime ?? false,
            updatedAt: now
        ).save()
        WidgetCenter.shared.reloadAllTimelines()

        let today = calendar.startOfDay(for: now)
        let weekAhead = calendar.date(byAdding: .day, value: 7, to: today) ?? now
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let stats = DigestStats(
            openTodos: open.count,
            dueThisWeek: open.filter { entry in
                guard let deadline = entry.deadline else { return false }
                return deadline >= today && deadline < weekAhead
            }.count,
            overdue: open.filter { entry in
                guard let deadline = entry.deadline else { return false }
                return DeadlineLabel.isOverdue(deadline, hasTime: entry.deadlineHasTime, now: now, calendar: calendar)
            }.count,
            linksThisWeek: all.filter { $0.hasLink && $0.createdAt >= weekAgo }.count,
            notesThisWeek: all.filter { $0.isNote && $0.createdAt >= weekAgo }.count
        )
        let digest = DigestComposer.compose(stats)
        let enabled = AppSettings.digestEnabled
        let weekday = AppSettings.digestWeekday
        let hour = AppSettings.digestHour
        Task {
            await notifications.syncDigest(digest, enabled: enabled, weekday: weekday, hour: hour)
        }
    }

    /// What iOS gives us when it wakes the app in the background.
    func backgroundRefresh() async {
        importInbox()
        await classifyBacklog()
        refreshDerived(immediately: true)
    }

    // MARK: - Helpers

    private func entry(id: UUID) -> Entry? {
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate<Entry> { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// False once an entry has been deleted; its properties must not be touched after that.
    private func isLive(_ entry: Entry) -> Bool {
        !entry.isDeleted && entry.modelContext != nil
    }

    private func save() {
        do {
            try context.save()
        } catch {
            log.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
