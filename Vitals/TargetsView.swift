import SwiftUI
import SwiftData
import Charts

struct TargetsView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.modelContext) private var context
    @Query(sort: \WeighIn.day, order: .reverse) private var weighIns: [WeighIn]

    @State private var newKg = ""
    @State private var newDate = Date.now

    private var targets: Targets { profileStore.targets(watchTDEE: health.watchTDEE30) }

    var body: some View {
        @Bindable var store = profileStore
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    bmiCard
                    energyCard
                    macroCard
                    formCard(store: $store)
                    weightCard
                    driCard
                    Text("Based on the US/Canada Dietary Reference Intakes and WHO guidance for a healthy adult of your age and sex. Protein and calories are personalised to your goal; the rest are population reference values. Not medical advice.")
                        .font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 4)
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Targets")
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: BMI

    private var bmiCard: some View {
        let t = targets, p = profileStore.profile
        let cat = t.bmiCategory
        let pos = max(0, min(1, (t.bmi - 15) / (40 - 15)))
        return Card(title: "Body mass index", subtitle: "WHO adult categories", symbol: "gauge.with.needle") {
            HStack(alignment: .firstTextBaseline) {
                Text(t.bmi.formatted(.number.precision(.fractionLength(1)))).font(.num(36)).monospacedDigit()
                Text("kg/m²").font(.caption).foregroundStyle(.secondary)
                Spacer()
                TonePill(text: cat.label, tone: cat.tone)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        Theme.info.frame(width: geo.size.width * 0.14); Theme.good.frame(width: geo.size.width * 0.26)
                        Theme.warn.frame(width: geo.size.width * 0.20); Theme.bad
                    }.clipShape(Capsule()).opacity(0.85).frame(height: 10)
                    Circle().fill(Color(.secondarySystemGroupedBackground)).frame(width: 20, height: 20)
                        .overlay(Circle().stroke(Color.primary, lineWidth: 3))
                        .offset(x: geo.size.width * pos - 10)
                        .animation(.spring(duration: 0.8), value: pos)
                }
            }.frame(height: 20).padding(.top, 6)
            HStack { Text("15"); Spacer(); Text("18.5"); Spacer(); Text("25"); Spacer(); Text("30"); Spacer(); Text("40") }
                .font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
            Text(bmiSentence(t, p)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func bmiSentence(_ t: Targets, _ p: Profile) -> String {
        var s = "At \(p.heightCm.g1) cm a healthy-weight range is \(t.healthyMin.g0)–\(t.healthyMax.g0) kg. "
        if p.weightKg > t.healthyMax { s += "You're \((p.weightKg - t.healthyMax).g1) kg above it. " }
        else if p.weightKg < t.healthyMin { s += "You're \((t.healthyMin - p.weightKg).g1) kg below it. " }
        else { s += "You're inside it, \((t.healthyMax - p.weightKg).g1) kg below the upper edge. " }
        return s + "BMI ignores muscle mass — treat it as one signal alongside waist size and how you feel."
    }

    // MARK: Energy

    private var energyCard: some View {
        let t = targets, p = profileStore.profile
        let goalTxt: String = switch p.goal {
        case .lose: "−\(t.dailyDelta.kcalString) kcal/day for \(p.rateKgPerWeek.g1) kg/week"
        case .gain: "+\(t.dailyDelta.kcalString) kcal/day for \(p.rateKgPerWeek.g1) kg/week"
        case .maintain: "eat what you burn"
        }
        var goalDate = ""
        if let w = t.weeksToGoal, p.goal != .maintain {
            let d = Date.now.adding(days: Int((w * 7).rounded()))
            goalDate = "\(p.targetWeightKg.g1) kg by ~\(d.formatted(.dateTime.day().month(.abbreviated).year())) (\(Int(w.rounded(.up))) wk)"
        }
        return Card(title: "Daily energy", subtitle: "Mifflin–St Jeor · \(t.age) yrs · \(p.sex.rawValue)", symbol: "flame") {
            HStack(spacing: 10) {
                tile("Resting (BMR)", t.bmr.kcalString, "What your body burns at complete rest.")
                tile("Total burn", t.tdee.kcalString, p.basis == .watch && t.tdeeWatch != nil ? "Apple Watch 30-day average. Formula says \(t.tdeeFormula.kcalString)." : "BMR × \(p.activity.g1) activity factor." + (t.tdeeWatch.map { " Watch measures \($0.kcalString)." } ?? ""))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("DAILY CALORIE TARGET").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).tracking(0.6)
                HStack(alignment: .firstTextBaseline, spacing: 3) { Text(t.target.kcalString).font(.num(30)).monospacedDigit(); Text("kcal").font(.caption).foregroundStyle(.secondary) }
                Text(goalTxt + (t.floored ? " — raised to a \(t.floor.kcalString) kcal safety floor." : "")).font(.caption).foregroundStyle(.secondary)
                if !goalDate.isEmpty { Text(goalDate).font(.caption).fontWeight(.semibold) }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Theme.emphasis.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.emphasis.opacity(0.4)))
        }
    }
    private func tile(_ k: String, _ v: String, _ d: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).tracking(0.5)
            HStack(alignment: .firstTextBaseline, spacing: 3) { Text(v).font(.num(21)).monospacedDigit(); Text("kcal").font(.caption2).foregroundStyle(.secondary) }
            Text(d).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Macros

    private var macroCard: some View {
        let t = targets, p = profileStore.profile
        let pk = t.proteinG * 4, ck = t.carbsG * 4, fk = t.fatG * 9, tot = max(1, pk + ck + fk)
        return Card(title: "Macro targets", subtitle: "\(p.proteinPerKg.g1) g protein/kg · 28% fat · rest carbs", symbol: "fork.knife") {
            HStack(spacing: 10) {
                macroTile("Protein", t.proteinG, pk, tot, Theme.protein)
                macroTile("Carbs", t.carbsG, ck, tot, Theme.carbs)
                macroTile("Fat", t.fatG, fk, tot, Theme.fat)
            }
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Theme.protein.frame(width: geo.size.width * pk / tot)
                    Theme.carbs.frame(width: geo.size.width * ck / tot)
                    Theme.fat
                }.clipShape(Capsule())
            }.frame(height: 12)
        }
    }
    private func macroTile(_ l: String, _ g: Double, _ k: Double, _ tot: Double, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(l.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(c).tracking(0.5)
            HStack(alignment: .firstTextBaseline, spacing: 2) { Text(g.g0).font(.num(21)).monospacedDigit(); Text("g").font(.caption2).foregroundStyle(.secondary) }
            Text("\(k.kcalString) kcal · \(Int((k / tot * 100).rounded()))%").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Form

    private func formCard(store: Bindable<ProfileStore>) -> some View {
        Card(title: "Your numbers", subtitle: "Saved automatically", symbol: "person.text.rectangle") {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    numberField("Weight (kg)", value: store.profile.weightKg, step: 0.1)
                    numberField("Height (cm)", value: store.profile.heightCm, step: 0.5)
                }
                DatePicker("Date of birth", selection: store.profile.dob, displayedComponents: .date).font(.subheadline)
                Picker("Sex", selection: store.profile.sex) { Text("Male").tag(Sex.male); Text("Female").tag(Sex.female) }.pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 6) {
                    Text("ENERGY EXPENDITURE BASIS").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).tracking(0.5)
                    Picker("Basis", selection: store.profile.basis) { Text("Apple Watch").tag(EnergyBasis.watch); Text("Activity level").tag(EnergyBasis.formula) }.pickerStyle(.segmented)
                    Text(health.watchTDEE30.map { "Your Apple Watch has averaged \($0.kcalString) kcal/day (resting + active) over the last 30 days." } ?? "No recent Apple Watch energy data yet — the formula uses your activity level.").font(.caption2).foregroundStyle(.secondary)
                }
                if profileStore.profile.basis == .formula || health.watchTDEE30 == nil {
                    Picker("Activity level", selection: store.profile.activity) {
                        Text("Sedentary (×1.2)").tag(1.2); Text("Light, 1–3 days/wk (×1.375)").tag(1.375); Text("Moderate, 3–5 days/wk (×1.55)").tag(1.55)
                        Text("Active, 6–7 days/wk (×1.725)").tag(1.725); Text("Very active (×1.9)").tag(1.9)
                    }.font(.subheadline)
                }
                Picker("Goal", selection: store.profile.goal) { ForEach(Goal.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                if profileStore.profile.goal != .maintain {
                    Picker("Pace", selection: store.profile.rateKgPerWeek) {
                        Text("0.25 kg/week — gentle").tag(0.25); Text("0.5 kg/week — recommended").tag(0.5); Text("0.75 kg/week — brisk").tag(0.75); Text("1 kg/week — aggressive").tag(1.0)
                    }.font(.subheadline)
                    numberField("Goal weight (kg)", value: store.profile.targetWeightKg, step: 0.5)
                }
                Picker("Protein", selection: store.profile.proteinPerKg) {
                    Text("1.2 g/kg — general health").tag(1.2); Text("1.6 g/kg — active").tag(1.6); Text("1.8 g/kg — fat loss, keep muscle").tag(1.8); Text("2.2 g/kg — building muscle").tag(2.2)
                }.font(.subheadline)
            }
        }
    }
    private func numberField(_ label: String, value: Binding<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).tracking(0.5)
            TextField(label, value: value, format: .number.precision(.fractionLength(0...1))).keyboardType(.decimalPad).font(.num(17, weight: .semibold)).monospacedDigit()
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: Weight

    private var weightCard: some View {
        let p = profileStore.profile, t = targets
        var points = weighIns.map { (day: $0.day, kg: $0.kg) }
        if let w = health.latestWeightKg, points.isEmpty { points.append((day: Date.now.startOfDay, kg: w)) }
        points.sort { $0.day < $1.day }
        let vals = points.map(\.kg) + (p.goal != .maintain ? [p.targetWeightKg] : [])
        let lo = (vals.min() ?? 60) - 2, hi = (vals.max() ?? 100) + 2
        return Card(title: "Weight", subtitle: points.last.map { "latest \($0.kg.g1) kg" } ?? "Log your first weigh-in", symbol: "scalemass") {
            if points.isEmpty {
                EmptyHint(title: "No weigh-ins yet", text: "Weigh-ins you log below appear here alongside your goal, and are written to Apple Health.")
            } else {
                Chart {
                    RectangleMark(yStart: .value("min", max(lo, t.healthyMin)), yEnd: .value("max", min(hi, t.healthyMax))).foregroundStyle(Theme.good.opacity(0.10))
                    if p.goal != .maintain {
                        RuleMark(y: .value("Goal", p.targetWeightKg)).foregroundStyle(Theme.emphasis).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                            .annotation(position: .top, alignment: .trailing) { Text("goal \(p.targetWeightKg.g1) kg").font(.caption2).foregroundStyle(.secondary) }
                    }
                    ForEach(points, id: \.day) { pt in
                        LineMark(x: .value("Day", pt.day), y: .value("kg", pt.kg)).foregroundStyle(Theme.protein).interpolationMethod(.catmullRom)
                        PointMark(x: .value("Day", pt.day), y: .value("kg", pt.kg)).foregroundStyle(Theme.protein).symbolSize(40)
                    }
                }
                .chartYScale(domain: lo...hi)
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in AxisGridLine(); AxisValueLabel().font(.caption2) } }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.caption2) } }
                .frame(height: 150)
            }
            HStack(alignment: .bottom, spacing: 8) {
                DatePicker("", selection: $newDate, in: ...Date.now, displayedComponents: .date).labelsHidden()
                TextField("kg", text: $newKg).keyboardType(.decimalPad).font(.num(16, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button { addWeight() } label: { Label("Log", systemImage: "plus").fontWeight(.bold) }.buttonStyle(.borderedProminent).tint(.primary).foregroundStyle(Color(.systemBackground))
                    .disabled(Double(newKg.replacingOccurrences(of: ",", with: ".")) == nil)
            }
            if !weighIns.isEmpty {
                ForEach(weighIns.prefix(8)) { w in
                    HStack {
                        Text(w.day.formatted(.dateTime.day().month(.abbreviated).year())).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(w.kg.g1) kg").font(.num(13, weight: .semibold)).monospacedDigit()
                        Button(role: .destructive) { context.delete(w); try? context.save() } label: { Image(systemName: "xmark").font(.caption2) }.buttonStyle(.plain).foregroundStyle(.tertiary).padding(.leading, 6)
                    }
                }
            }
        }
    }
    private func addWeight() {
        guard let kg = Double(newKg.replacingOccurrences(of: ",", with: ".")), kg > 30, kg < 300 else { return }
        let day = newDate.startOfDay
        if let e = weighIns.first(where: { $0.day == day }) { e.kg = kg } else { context.insert(WeighIn(day: day, kg: kg)) }
        try? context.save()
        if day >= (weighIns.first?.day ?? .distantPast) { profileStore.profile.weightKg = (kg * 10).rounded() / 10 }
        Task { await health.write(weightKg: kg, on: day) }
        newKg = ""
    }

    // MARK: Reference intake

    private var driCard: some View {
        let t = targets, p = profileStore.profile
        let why: [Nutrient: String] = [
            .kcal: "From your goal", .protein: "\(p.proteinPerKg.g1) g × \(p.weightKg.g1) kg", .carbs: "Remainder after protein & fat", .fat: "28% of calories",
            .satFat: "<10% of calories (WHO)", .fiber: "DRI adequate intake", .sugar: "<10% of calories, free sugars", .sodium: "DRI upper limit",
            .cholesterol: "Dietary guideline", .potassium: "DRI adequate intake", .calcium: "DRI recommended", .iron: "DRI recommended",
            .vitaminC: "DRI recommended", .vitaminD: "DRI (600 IU); more if blood level is low",
        ]
        return Card(title: "Daily reference intake", subtitle: "\(p.sex == .female ? "Woman" : "Man"), \(t.age) · \(t.target.kcalString) kcal plan", symbol: "list.bullet.rectangle") {
            VStack(spacing: 0) {
                ForEach(Nutrient.allCases) { n in
                    HStack(alignment: .firstTextBaseline) {
                        Text(n.label).font(.subheadline).fontWeight(.medium)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(n.kind == .max ? "≤ " : n.kind == .min ? "≥ " : "")\(t.reference[safe: n].g0) \(n.unit)").font(.num(13, weight: .semibold)).monospacedDigit()
                            Text(why[n] ?? "").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 7)
                    Divider()
                }
                HStack { Text("Water").font(.subheadline).fontWeight(.medium); Spacer(); VStack(alignment: .trailing, spacing: 1) { Text("~\(t.waterL.g1) L").font(.num(13, weight: .semibold)); Text("DRI total fluid, incl. food").font(.caption2).foregroundStyle(.tertiary) } }.padding(.vertical, 7)
            }
        }
    }
}
