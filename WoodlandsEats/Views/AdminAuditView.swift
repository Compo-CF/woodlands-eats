import SwiftUI

/// v1.8 (integrity audit): admin-only screen that runs AuditService
/// against the full CloudKit Placement corpus and lists flagged
/// signals ranked by severity.
///
/// Accessed from ProfileView admin section as a NavigationLink so it
/// doesn't slow down the initial Profile load — the CloudKit walk
/// only happens when the admin explicitly taps in.
///
/// UI shape:
///   - Header: summary line + last-run timestamp + refresh button
///   - Grouped list: signals sorted by severity (HIGH → MEDIUM → LOW),
///     each row showing severity dot, category icon, title, and a
///     tap-expand for the full detail + evidence.
struct AdminAuditView: View {
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(RestaurantStore.self) private var store
    @State private var report: AuditReport?
    @State private var loading = false
    @State private var expandedSignalID: UUID?

    private let audit = AuditService()

    var body: some View {
        Group {
            if loading {
                ProgressView("Fetching placements…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let report {
                reportView(report)
            } else {
                emptyState
            }
        }
        .navigationTitle("Placement Audit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await runAudit() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(loading)
            }
        }
        .task {
            if report == nil { await runAudit() }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Run an audit", systemImage: "shield.checkered")
        } description: {
            Text("Tap the refresh icon to page all Placement records from CloudKit and check for gaming patterns.")
        }
    }

    @ViewBuilder
    private func reportView(_ report: AuditReport) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(report.signals.count) signal\(report.signals.count == 1 ? "" : "s") across \(report.totalPlacements) placements from \(report.totalUsers) users on \(report.totalRestaurantsRanked) restaurants")
                        .font(.subheadline)
                    Text("Generated \(report.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if report.signals.isEmpty {
                Section {
                    Label("No suspicious patterns flagged.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
            } else {
                // Group signals by severity so the admin's eye lands on
                // High first, without scanning past low-severity noise.
                ForEach([AuditSignal.Severity.high, .medium, .low], id: \.self) { sev in
                    let group = report.signals.filter { $0.severity == sev }
                    if !group.isEmpty {
                        Section(header: sectionHeader(for: sev, count: group.count)) {
                            ForEach(group) { signal in
                                signalRow(signal)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func sectionHeader(for severity: AuditSignal.Severity, count: Int) -> some View {
        HStack {
            Circle()
                .fill(color(for: severity))
                .frame(width: 8, height: 8)
            Text("\(severity.displayName) severity")
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func signalRow(_ signal: AuditSignal) -> some View {
        let expanded = expandedSignalID == signal.id
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: signal.category.systemImage)
                    .foregroundStyle(color(for: signal.severity))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(signal.title)
                        .font(.subheadline.weight(.semibold))
                    Text(signal.category.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            if expanded {
                Text(signal.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 32)
                if let rid = signal.restaurantID,
                   let restaurant = store.restaurants.first(where: { $0.id == rid }) {
                    Text("Restaurant: \(restaurant.name)")
                        .font(.caption.weight(.medium))
                        .padding(.leading, 32)
                }
                if let uid = signal.userID {
                    Text("User: \(uid.prefix(20))…")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.leading, 32)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy) {
                expandedSignalID = expanded ? nil : signal.id
            }
        }
    }

    private func color(for severity: AuditSignal.Severity) -> Color {
        switch severity {
        case .high: .red
        case .medium: .orange
        case .low: .yellow
        }
    }

    private func runAudit() async {
        loading = true
        let placements = await cloudKit.fetchAllPlacementsForAudit()
        report = audit.analyze(placements)
        loading = false
    }
}
