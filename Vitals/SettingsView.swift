import SwiftUI

struct SettingsView: View {
    @Environment(HealthKitManager.self) private var health
    @State private var apiKey = Keychain.read(ClaudeService.keyAccount) ?? ""
    @State private var usdaKey = Keychain.read(FoodLookup.usdaKeyAccount) ?? ""
    @State private var saved = false
    @State private var showKey = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Photo recognition", value: "On-device (Apple Vision)")
                    LabeledContent("Nutrition data", value: "USDA + Open Food Facts")
                    LabeledContent("Text parsing", value: FoodLookup.onDeviceModelAvailable ? "Apple on-device model" : "Keyword matching")
                    LabeledContent("Coach", value: FoodLookup.onDeviceModelAvailable ? "Apple on-device model" : ClaudeService.shared.hasKey ? "Claude" : "Rules only")
                } header: {
                    Text("How lookups work — free")
                } footer: {
                    Text("Nothing here costs anything or needs an account. Foods in a photo are recognised on your phone; nutrients come from a built-in table of ~110 everyday, Portuguese and Sri Lankan foods, the USDA FoodData Central database, and Open Food Facts for barcodes. Portions start at a typical serving — adjust the grams before saving.\(FoodLookup.onDeviceModelAvailable ? "" : " Apple's on-device model (iPhone 15 Pro or newer, iOS 26) makes text parsing and the coach smarter when available.")")
                }

                Section("Apple Health") {
                    if health.isAvailable {
                        LabeledContent("Status", value: health.authorizationRequested ? "Connected" : "Not connected")
                        Button("Reconnect / review permissions") { Task { await health.requestAuthorization() } }
                        if let d = health.lastRefresh { LabeledContent("Last read", value: d.formatted(date: .abbreviated, time: .shortened)) }
                        Text("Reads steps, energy, heart rate, sleep, weight and height. Writes every meal you log (calories + 13 nutrients) and your weigh-ins, so the Health app stays the single record. Change access any time in Settings → Health → Data Access & Devices → Vitals.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Apple Health is not available on this device.").foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack {
                        Group {
                            if showKey { TextField("sk-ant-…", text: $apiKey) } else { SecureField("sk-ant-…", text: $apiKey) }
                        }
                        .textInputAutocapitalization(.never).autocorrectionDisabled().font(.system(.body, design: .monospaced))
                        Button { showKey.toggle() } label: { Image(systemName: showKey ? "eye.slash" : "eye") }.buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    Button(saved ? "Saved" : "Save key") {
                        Keychain.write(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), account: ClaudeService.keyAccount)
                        saved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    if ClaudeService.shared.hasKey {
                        Button("Remove key (back to free)", role: .destructive) { Keychain.delete(ClaudeService.keyAccount); apiKey = "" }
                    }
                } header: {
                    Text("Optional: Claude for better photo estimates")
                } footer: {
                    Text("Off by default. If you add an Anthropic API key, photo and text lookups use Claude, which can judge portions from the plate and recognise mixed dishes — at roughly 3–8 cents per photo on your own account. Stored in the iOS Keychain on this device only.")
                }

                Section {
                    TextField("USDA API key (optional)", text: $usdaKey).textInputAutocapitalization(.never).autocorrectionDisabled().font(.system(.body, design: .monospaced))
                        .onSubmit { Keychain.write(usdaKey.trimmingCharacters(in: .whitespaces), account: FoodLookup.usdaKeyAccount) }
                    Button("Save USDA key") { Keychain.write(usdaKey.trimmingCharacters(in: .whitespaces), account: FoodLookup.usdaKeyAccount) }.disabled(usdaKey.isEmpty)
                } header: {
                    Text("Optional: USDA key")
                } footer: {
                    Text("Free. The built-in demo key allows about 30 lookups an hour; if you hit that, get your own instant key at fdc.nal.usda.gov/api-key-signup.")
                }

                Section {
                    LabeledContent("Version", value: "1.0")
                } footer: {
                    Text("Calorie targets use the Mifflin–St Jeor equation, or your Apple Watch's measured 30-day energy expenditure when available. A 0.5 kg/week goal is a 550 kcal/day deficit. Vitals is a personal tool built from your own data — not medical advice.")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
