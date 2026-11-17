import PickupCore
import SwiftUI

public struct RootShellView: View {
    @Bindable var store: AppStore

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            if !store.preferences.tutorialCompleted && !store.showLaunchIntro {
                OnboardingView(store: store)
                    .transition(.opacity)
            } else if store.isLocked {
                PrivacyLockView(store: store)
                    .transition(.opacity)
            } else {
                AdaptiveMainView(store: store)
            }

            if store.showLaunchIntro {
                LaunchIntroOverlay(palette: store.palette) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        store.showLaunchIntro = false
                    }
                    Task {
                        await store.checkDailyRevisitAfterLaunch()
                    }
                }
                .zIndex(100)
            }

            // Floating Glass Toast Overlay
            if let toast = store.toastMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(store.palette.accent)
                        Text(toast)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(store.palette.primaryText)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .pickupGlassCapsule()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 86)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(90)
                .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: store.toastMessage)
        .sheet(item: $store.dailyRevisitSheetEntry) { entry in
            NavigationStack {
                RevisitEntryDetailView(store: store, initialEntry: entry, isDailyModal: true)
            }
        }
    }
}
