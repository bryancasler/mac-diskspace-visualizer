import SwiftUI

struct SettingsView: View {
    @AppStorage("menuBarEnabled") private var menuBarEnabled = true
    @AppStorage(FreeSpaceWatcher.alertsEnabledKey) private var alertsEnabled = false
    @AppStorage(FreeSpaceWatcher.thresholdKey) private var thresholdGB = 20.0

    var body: some View {
        Form {
            Section {
                Toggle("Show free space in the menu bar", isOn: $menuBarEnabled)
            }
            Section {
                Toggle("Notify when startup disk space is low", isOn: $alertsEnabled)
                    .onChange(of: alertsEnabled) {
                        if alertsEnabled {
                            FreeSpaceWatcher.requestNotificationPermission()
                        }
                    }
                if alertsEnabled {
                    HStack {
                        Text("Warn below")
                        TextField("GB", value: $thresholdGB, format: .number)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                        Text("GB free")
                            .foregroundStyle(.secondary)
                    }
                    Text("Checked every 5 minutes; at most one notification per day.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize()
    }
}
