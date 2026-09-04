import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var showingDataSources: Bool
    @State private var handledDebugRoute = false

    var body: some View {
        Form {
            Section("Health data") {
                healthConnectionRow
                NavigationLink {
                    DataSourcesView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Manage Data & Sources", systemImage: "slider.horizontal.3")
                            .font(.headline)
                        Text("Choose what appears on Today, what shapes the recommendation, and which Apple Health source is used.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }

            Section {
                statusRow("Calendar", status: appModel.calendarStatus, symbol: "calendar")
                statusRow("Wake alarms", status: appModel.alarmStatus, symbol: "alarm.fill")
            } header: {
                Text("Plan integrations")
            } footer: {
                Text("Connect Calendar and request wake-alarm access from Plan, when you apply a schedule.")
            }

            Section("Exercise library") {
                Link(destination: ExerciseCatalogSource.homepageURL) {
                    Label(ExerciseCatalogSource.attribution, systemImage: "figure.strengthtraining.traditional")
                }
                Link("View dataset license", destination: ExerciseCatalogSource.licenseURL)
                    .font(.subheadline)
                Text("The catalog and illustrations download from RepDB and are cached on this device. Sleep and workout records are never sent with those requests.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy and limits") {
                Label("On-device storage only", systemImage: "iphone.gen3")
                Label("No account, server, ads, or analytics", systemImage: "hand.raised.fill")
                Label("Wellness guidance—not diagnosis", systemImage: "cross.case")
                Text("Apple Health may return no samples when a read category is denied. Sleep Coach reports only what it can verify: query health, received samples, freshness, and source provenance.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
        .navigationDestination(isPresented: $showingDataSources) {
            DataSourcesView()
        }
        .task {
            #if DEBUG
            guard !handledDebugRoute,
                  ProcessInfo.processInfo.arguments.contains(where: {
                      $0 == "--show-data-sources" || $0.hasPrefix("--show-signal-source=")
                  }) else { return }
            handledDebugRoute = true
            showingDataSources = true
            #endif
        }
    }

    private var healthConnectionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow("Apple Health", status: appModel.healthStatus, symbol: "heart.fill")
            if appModel.healthConnectionState.canRequestAccess {
                Button("Request access") {
                    Task { await appModel.connectHealth() }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    @ViewBuilder
    private func statusRow(_ title: String, status: String, symbol: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: symbol)
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        } else {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Text(status).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
        }
    }
}
