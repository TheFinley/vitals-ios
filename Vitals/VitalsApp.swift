import SwiftUI
import SwiftData

@main
struct VitalsApp: App {
    @State private var health = HealthKitManager()
    @State private var profileStore = ProfileStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(health)
                .environment(profileStore)
                .task {
                    if health.isAvailable { await health.requestAuthorization() }
                    seedProfileFromHealth()
                }
        }
        .modelContainer(for: [Meal.self, WeighIn.self])
    }

    /// First launch: take weight, height, date of birth and sex from Apple Health so the
    /// calculator opens with real numbers instead of placeholders.
    private func seedProfileFromHealth() {
        guard !profileStore.profile.hasSeededFromHealth else { return }
        var p = profileStore.profile
        if let w = health.latestWeightKg { p.weightKg = (w * 10).rounded() / 10; p.targetWeightKg = (w - 6).rounded() }
        if let h = health.latestHeightCm { p.heightCm = (h * 2).rounded() / 2 }
        if let d = health.dateOfBirth { p.dob = d }
        if let s = health.biologicalSex { p.sex = s }
        if health.latestWeightKg != nil || health.latestHeightCm != nil { p.hasSeededFromHealth = true }
        profileStore.profile = p
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            TodayView().tabItem { Label("Today", systemImage: "gauge.with.dots.needle.33percent") }
            FoodLogView().tabItem { Label("Food", systemImage: "camera.viewfinder") }
            TargetsView().tabItem { Label("Targets", systemImage: "target") }
            CoachView().tabItem { Label("Coach", systemImage: "sparkles") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.emphasis)
    }
}
