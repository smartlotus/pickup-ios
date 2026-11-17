import BackgroundTasks
import PickupCore
import SwiftUI
import UIKit

@main
struct PickupIOSApp: App {
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootShellView(store: store)
                .preferredColorScheme(.dark)
                .task {
                    await store.bootstrap()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
                    await store.checkScheduledAutoBackup(trigger: .scheduled)
                    await store.checkDailyRevisitAfterLaunch()
                }
            case .background:
                store.scheduleBackgroundRefreshTask()
                if store.preferences.autoBackup.isEnabled && store.preferences.autoBackup.frequency == .onAppBackground {
                    let bgId = UIApplication.shared.beginBackgroundTask(withName: "PickupAutoBackup")
                    Task {
                        await store.checkScheduledAutoBackup(trigger: .background)
                        if bgId != .invalid {
                            UIApplication.shared.endBackgroundTask(bgId)
                        }
                    }
                }
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(AppStore.backgroundTaskIdentifier)) {
            await store.checkScheduledAutoBackup(trigger: .scheduled)
            await MainActor.run {
                store.scheduleBackgroundRefreshTask()
            }
        }
    }
}
