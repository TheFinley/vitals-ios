import SwiftUI
import SwiftData

/// Rule-based observations from the last 7 days, plus an on-demand coach (on-device model, or Claude if a key is set).
struct CoachView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(ProfileStore.self) private var profileStore
    @Query(sort: \Meal.time) private var allMeals: [Meal]

    @State private var coach: [CoachSuggestion] = []
    @State private var coachStatus = "Uses your targets and the last 7 days of your log to suggest specific meals for the rest of today."
    @State private var loading = false

    private var targets: Targets { profileStore.targets(watchTDEE: health.watchTDEE30) }
    private var last7: [Date] { (0..<7).reversed().map { Date.now.startOfDay.adding(days: -$0) } }
    private func totals(on d: Date) -> Totals { allMeals.filter { $0.day == d }.map(\.totals).reduce(.zero, +) }
    private var loggedDays: [Date] { last7.filter { d in allMeals.contains { $0.day == d } } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    observationsCard
                    coachCard
                    swapsCard
                    Text("General nutrition guidance generated from your own log — not medical advice. Check with a doctor or dietitian before large dietary changes.")
                        .font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 4)
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Coach")
        }
    }

    // MARK: Rule-based

    struct Observation: Identifiable { let id = UUID(); var kind: CoachSuggestion.Kind; var title: String; var body: String }

    private var observations: [Observation] {
        let t = targets, p = profileStore.profile
        let days = loggedDays
        guard !days.isEmpty else { return [] }
        let n = Double(days.count)
        func avg(_ k: Nutrient) -> Double { days.map { totals(on: $0)[safe: k] }.reduce(0, +) / n }
        var out: [Observation] = []
        let k = avg(.kcal)
        if p.goal == .lose {
            if k > t.target + 150 { out.append(.init(kind: .avoid, title: "Running over your deficit", body: "Averaging \(k.kcalString) kcal on logged days against a \(t.target.kcalString) target. Trim the biggest single item each day — usually the drink, the sauce or the second helping — rather than skipping meals.")) }
            else if k < t.floor - 100 { out.append(.init(kind: .tip, title: "Eating too little", body: "\(k.kcalString) kcal/day is below a safe floor for your size. Under-eating stalls fat loss and costs muscle — aim for at least \(t.floor.kcalString).")) }
            else { out.append(.init(kind: .eat, title: "Deficit on track", body: "\(k.kcalString) kcal/day on logged days, about \(max(0, t.tdee - k).kcalString) below what you burn — that projects to roughly \(((t.tdee - k) * 7 / 7700).formatted(.number.precision(.fractionLength(2)))) kg/week.")) }
        }
        let pr = avg(.protein)
        if pr < t.reference[safe: .protein] * 0.8 { out.append(.init(kind: .eat, title: "More protein at every meal", body: "\(pr.g0) g/day vs. a \(t.reference[safe: .protein].g0) g target. Eggs, skyr or Greek yoghurt, chicken, tinned tuna, dhal, tofu — 30–40 g per meal keeps you full and protects muscle while losing weight.")) }
        let fib = avg(.fiber)
        if fib < t.reference[safe: .fiber] * 0.7 { out.append(.init(kind: .eat, title: "Fibre is low", body: "\(fib.g1) g/day; aim for \(t.reference[safe: .fiber].g0) g. Oats, beans, lentils, whole fruit, vegetables and whole-grain bread — fibre also lowers LDL cholesterol, which was high on your Mar 2025 panel.")) }
        let sf = avg(.satFat)
        if sf > t.reference[safe: .satFat] { out.append(.init(kind: .avoid, title: "Saturated fat over 10% of calories", body: "\(sf.g1) g/day vs. a \(t.reference[safe: .satFat].g0) g limit. Given your cholesterol history, swap butter, fatty cuts, pastries and coconut-heavy curries for olive oil, fish and leaner meat.")) }
        let su = avg(.sugar)
        if su > t.reference[safe: .sugar] { out.append(.init(kind: .avoid, title: "Sugar above the limit", body: "\(su.g0) g/day vs. \(t.reference[safe: .sugar].g0) g. Sweetened drinks, juices, pastéis and flavoured yoghurts add up fast — whole fruit instead.")) }
        let na = avg(.sodium)
        if na > t.reference[safe: .sodium] { out.append(.init(kind: .avoid, title: "Sodium is high", body: "\(na.g0) mg/day vs. a 2,300 mg limit. Cured meats, bacalhau, instant noodles, soy sauce and packaged snacks are the usual sources.")) }
        let vd = avg(.vitaminD)
        if vd < t.reference[safe: .vitaminD] * 0.5 { out.append(.init(kind: .eat, title: "Vitamin D from food is low", body: "Your Apr 2025 blood test showed insufficient vitamin D. Oily fish (sardines, mackerel, salmon), eggs and fortified milk help; sunlight and a supplement do most of the work — worth asking your doctor.")) }
        let kk = avg(.potassium)
        if kk < t.reference[safe: .potassium] * 0.6 { out.append(.init(kind: .eat, title: "More potassium-rich foods", body: "\(kk.g0) mg/day; aim for \(t.reference[safe: .potassium].g0). Bananas, potatoes, beans, spinach, yoghurt and tomatoes — it also helps offset sodium.")) }
        if days.count < 4 { out.append(.init(kind: .tip, title: "Log a few more days", body: "Only \(days.count) of the last 7 days have meals. Three or four consistent days make these suggestions a lot more reliable than one big day.")) }
        return out
    }

    private var observationsCard: some View {
        let obs = observations
        return Card(title: "What to eat, what to skip", subtitle: obs.isEmpty ? "Log a meal to get observations" : "\(obs.count) from the last 7 days", symbol: "sparkles") {
            if obs.isEmpty {
                EmptyHint(title: "Nothing to observe yet", text: "Once you've logged a day or two of meals, this fills in with what's running high or low against your targets.")
            } else {
                ForEach(obs) { o in SuggestionRow(kind: o.kind, title: o.title, body_: o.body) }
            }
        }
    }

    // MARK: Claude coach

    private var coachCard: some View {
        Card(title: "Ask the coach about today", subtitle: ClaudeService.shared.hasKey ? "Claude" : FoodLookup.onDeviceModelAvailable ? "On-device" : nil, symbol: "sparkles") {
            Text(coachStatus).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(coach) { s in SuggestionRow(kind: s.kind, title: s.title, body_: s.body) }
            Button { Task { await askCoach() } } label: {
                HStack { if loading { ProgressView().tint(.white) }; Text(loading ? "Thinking…" : coach.isEmpty ? "Get suggestions" : "Ask again").fontWeight(.bold) }
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).tint(Theme.emphasis).foregroundStyle(.white)
            .disabled(loading || !(ClaudeService.shared.hasKey || FoodLookup.onDeviceModelAvailable))
            Text(ClaudeService.shared.hasKey ? "Runs on Claude with your API key." : FoodLookup.onDeviceModelAvailable ? "Runs on Apple's on-device model — free and private." : "Needs Apple Intelligence (iPhone 15 Pro or newer, iOS 26) — or add a Claude API key in Settings. The observations above work on every phone.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func askCoach() async {
        loading = true; coachStatus = "Thinking… usually 10–40 seconds."
        let t = targets, p = profileStore.profile
        func round(_ tot: Totals) -> [String: Int] { Dictionary(uniqueKeysWithValues: [Nutrient.kcal, .protein, .carbs, .fat, .satFat, .fiber, .sugar, .sodium].map { ($0.jsonKey, Int(tot[safe: $0].rounded())) }) }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
        let log: [[String: Any]] = loggedDays.map { d in
            ["date": f.string(from: d),
             "meals": allMeals.filter { $0.day == d }.map { ["slot": $0.slot.rawValue, "name": $0.displayName, "items": $0.items.map(\.name), "kcal": Int($0.totals[safe: .kcal].rounded())] },
             "totals": round(totals(on: d))]
        }
        let ctx: [String: Any] = [
            "today": f.string(from: .now), "hourNow": Calendar.current.component(.hour, from: .now),
            "profile": ["age": t.age, "sex": p.sex.rawValue, "weightKg": p.weightKg, "heightCm": p.heightCm, "bmi": (t.bmi * 10).rounded() / 10, "goal": p.goal.rawValue,
                        "paceKgPerWeek": p.rateKgPerWeek, "city": "Lisbon, Portugal", "background": "Sri Lankan; enjoys rice & curry, also Portuguese food",
                        "health": "LDL cholesterol was high in Mar 2025 (normal by Apr 2025); vitamin D insufficient Apr 2025; runs ~3x/week, ~15k steps/day"],
            "dailyTargets": Dictionary(uniqueKeysWithValues: Nutrient.allCases.map { ($0.jsonKey, Int(t.reference[safe: $0].rounded())) }),
            "eatenToday": round(totals(on: .now.startOfDay)),
            "todaySoFar": ["steps": Int(health.today.steps), "activeKcal": Int(health.today.activeKcal)],
            "last7Days": log,
        ]
        do {
            let json = try JSONSerialization.data(withJSONObject: ctx)
            let ctxString = String(decoding: json, as: UTF8.self)
            if ClaudeService.shared.hasKey {
                coach = try await ClaudeService.shared.coach(context: ctxString)
            } else if let local = await FoodLookup.onDeviceCoach(context: ctxString) {
                coach = local
            } else {
                coach = []
            }
            coachStatus = coach.isEmpty ? "No suggestions came back — try again in a moment." : "Suggestions for \(Date.now.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))) · \(Date.now.formatted(date: .omitted, time: .shortened))"
        } catch {
            coachStatus = error.localizedDescription
        }
        loading = false
    }

    // MARK: Static swaps

    private var swapsCard: some View {
        let lose = profileStore.profile.goal == .lose
        return Card(title: "Everyday swaps", subtitle: "Lisbon + Sri Lankan kitchen", symbol: "arrow.left.arrow.right") {
            list("LEAN ON THESE", Theme.good, [
                ("Grilled fish", "sardines, dourada, mackerel: protein, omega-3 and vitamin D in one plate."),
                ("Eggs, skyr, cottage cheese", "cheap high-protein breakfasts that keep you full until lunch."),
                ("Dhal, chickpeas, black beans", "fibre and protein; a small bowl of dhal with less coconut milk is a solid weight-loss curry."),
                ("Vegetables first", "fill half the plate before rice; red or brown rice over white when you can."),
                ("Whole fruit, oats, a handful of nuts", "snacks with fibre and fat that don't spike sugar."),
                ("Water, black coffee, plain tea", "\(targets.waterL.g1) L of fluid a day; a large glass before meals helps portion control."),
            ])
            list("GO EASY ON THESE", Theme.bad, [
                ("Sugary drinks and juice", "150–250 kcal a glass with zero fullness; the single easiest cut\(lose ? " on a deficit" : "")."),
                ("Pastéis, croissants, biscuits", "saturated fat plus sugar; keep to one or two a week."),
                ("Fried food and fatty cuts", "chouriço, bacon, deep-fried snacks push saturated fat and sodium past the limit quickly."),
                ("Coconut-milk-heavy curries and kottu", "delicious but calorie-dense; halve the coconut milk or the portion."),
                ("Alcohol", "7 kcal per gram and it lowers restraint around food; beer and cocktails are the worst offenders."),
                ("“Healthy” extras", "granola, dried fruit, smoothies and olive oil are good foods that are easy to overpour."),
            ])
        }
    }
    private func list(_ h: String, _ c: Color, _ items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(h).font(.system(size: 11, weight: .heavy)).foregroundStyle(c).tracking(0.6)
            ForEach(items, id: \.0) { it in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(c.opacity(0.5)).frame(width: 5, height: 5).padding(.top, 6)
                    (Text(it.0).fontWeight(.semibold) + Text(" — \(it.1)").foregroundStyle(.secondary)).font(.caption).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
