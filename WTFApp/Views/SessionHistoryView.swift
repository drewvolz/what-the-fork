// WTFApp/Views/SessionHistoryView.swift
import SwiftUI
import WTFCore

/// Replaces the idle screen. Shows all stored sessions as compact rows with
/// minimap thumbnails. Empty state shown when no sessions exist.
struct SessionHistoryView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var restoreQueue: RestoreQueue
    @Environment(\.openWindow) var openWindow

    var body: some View {
        if store.history.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Recent Sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                        Text("\(store.history.count) sessions")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)

                    ForEach(store.history) { session in
                        SessionHistoryRow(
                            session: session,
                            onRestore: {
                                restoreQueue.pending = session
                                openWindow(id: "session")
                            },
                            onDelete: { store.delete(id: session.id) }
                        )
                    }
                }
                .padding(12)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No sessions yet")
                .foregroundStyle(.secondary)
            Text("Run `wtf <command>` to capture your first build")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row

struct SessionHistoryRow: View {
    let session: StoredSession
    let onRestore: () -> Void
    let onDelete: () -> Void

    @State private var thumbnailData: (timeline: Timeline, criticalPathIDs: Set<Int>)?

    var body: some View {
        Button(action: onRestore) {
            HStack(spacing: 12) {
                thumbnailView
                    .frame(width: 56, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.commandName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(rowSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(relativeTimestamp)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .contextMenu {
            Button("Delete Session", role: .destructive, action: onDelete)
        }
        .task {
            guard thumbnailData == nil else { return }
            let root = TreeBuilder.buildTree(from: session.events, rootPID: session.rootPID)
            let maxEnd = root.allDescendants.compactMap(\.endTime).max()
            let duration = max(1.0, (maxEnd ?? root.startTime) - root.startTime)
            let tl = Timeline(rootNode: root, startTime: root.startTime, totalDuration: duration)
            let cpIDs = Set(CriticalPathFinder.findCriticalPath(root).map(\.id))
            thumbnailData = (tl, cpIDs)
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let (tl, cpIDs) = thumbnailData {
            MinimapThumbnailView(timeline: tl, criticalPathIDs: cpIDs)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.4))
        }
    }

    private var rowSubtitle: String {
        let dur = session.duration < 60
            ? String(format: "%.1fs", session.duration)
            : String(format: "%.0fm %.0fs", session.duration / 60, session.duration.truncatingRemainder(dividingBy: 60))
        let pct = String(format: "%.0f%%", session.parallelismScore * 100)
        return "\(dur) · \(pct) parallel"
    }

    private var relativeTimestamp: String {
        let cal = Calendar.current
        if cal.isDateInToday(session.timestamp) {
            let fmt = DateFormatter()
            fmt.dateFormat = "h:mm a"
            return fmt.string(from: session.timestamp)
        } else if cal.isDateInYesterday(session.timestamp) {
            return "Yesterday"
        } else {
            let fmt = DateFormatter()
            fmt.dateFormat = "EEE"
            return fmt.string(from: session.timestamp)
        }
    }
}
