import SwiftUI
import SwiftData
import Charts

struct TodayView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(ProfileStore.self) private var profileStore
    @Query(sort: \Meal.time) private var allMeals: [Meal]

    private var targets: Targets { profileStore.targets(watchTDEE: health.watchTDEE30) }
    private var todayMeals: [Meal] { allMeals.filter { $0.day == Date.now.startOfDay } }
    private var eaten: Double { todayMeals.map { $0.totals[safe: .kcal] }.reduce(0, +) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        StatTile(label: "steps today", value: health.today.steps.g0, symbol: "figure.walk", color: Theme.protein, detail: "goal 10,000")
                        StatTile(label: "active energy", value: health.today.activeKcal.g0, unit: "kcal", symbol: "flame.fill", color: Theme.fat, detail: health.today.basalKcal > 0 ? "+ \(health.today.basalKcal.g0) resting" : "resting energy pending")
                        StatTile(label: "resting heart rate", value: health.today.restingHR.map { $0.g0 } ?? "—", unit: "bpm", symbol: "heart.fill", color: Theme.heart, detail: "from Apple Watch")
                        StatTile(label: "last night", value: health.today.sleepHours.map { $0.g1 } ?? "—", unit: "hrs", symbol: "moon.fill", color: Theme.sleep, detail: "7–9 h target")
                    }
                    balanceCard
                    weekCard
                    if !health.isAvailable {
                        Card { Text("Apple Health isn't available on this device, so activity and energy show as zero. Everything else works.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .refreshable { await health.refresh() }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await health.refresh() } } label: { Image(systemName: "arrow.clockwise") } } }
        }
    }

    private var header: some View {
        let hr = Calendar.current.component(.hour, from: .now)
        let greeting = hr < 12 ? "Good morning" : hr < 18 ? "Good afternoon" : "Good evening"
        return VStack(alignment: .leading, spacing: 4) {
            Text("PERSONAL HEALTH").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary).tracking(0.8)
            Text(greeting).font(.system(size: 28, weight: .heavy, design: .rounded))
            HStack(spacing: 6) {
                let p = profileStore.profile
                let t = targets
                chip("\(p.age) yrs", "shield")
                chip("\(p.weightKg.g1) kg · BMI \(t.bmi.formatted(.number.precision(.fractionLength(1))))", "gauge.with.needle")
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
    }
    private func chip(_ t: String, _ s: String) -> some View {
        Label(t, systemImage: s).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 6).background(Color(.secondarySystemGroupedBackground), in: Capsule())
    }

    private var balanceCard: some View {
        let t = targets
        let burned = health.today.burned ?? t.tdee
        let remain = t.target - eaten
        return Card(title: "Energy balance", subtitle: health.today.burned != nil ? "Burned from Apple Watch" : "Burned estimated", symbol: "scalemass") {
            HStack(spacing: 16) {
                ZStack {
                    Ring(progress: t.target > 0 ? eaten / t.target : 0, color: Theme.emphasis, lineWidth: 10)
                    VStack(spacing: 0) {
                        Text(abs(remain).kcalString).font(.num(22)).monospacedDigit().foregroundStyle(remain < 0 ? Theme.bad : .primary)
                        Text(remain >= 0 ? "LEFT" : "OVER").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    }
                }.frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 6) {
                    row("Eaten", eaten.kcalString + " kcal", Theme.emphasis)
                    row("Target", t.target.kcalString + " kcal", .secondary)
                    row("Burned", burned.kcalString + " kcal", Theme.fat)
                    let net = burned - eaten
                    Text(net >= 0 ? "Net −\(net.kcalString) kcal so far today" : "Net +\((-net).kcalString) kcal so far today").font(.caption).foregroundStyle(net >= 0 ? Theme.good : Theme.bad).padding(.top, 2)
                }
                Spacer()
            }
        }
    }
    private func row(_ k: String, _ v: String, _ c: Color) -> some View {
        HStack { Circle().fill(c).frame(width: 7, height: 7); Text(k).font(.caption).foregroundStyle(.secondary); Spacer(); Text(v).font(.num(14, weight: .semibold)).monospacedDigit() }
    }

    private var weekCard: some View {
        let t = targets
        let days = (0..<14).reversed().map { Date.now.startOfDay.adding(days: -$0) }
        let data = days.map { d in (day: d, eaten: allMeals.filter { $0.day == d }.map { $0.totals[safe: .kcal] }.reduce(0, +), burned: health.burnedByDay[d]) }
        return Card(title: "Last 14 days", subtitle: "Eaten vs. target and burned", symbol: "chart.bar") {
            Chart {
                ForEach(data, id: \.day) { x in
                    if let b = x.burned {
                        BarMark(x: .value("Day", x.day, unit: .day), y: .value("Burned", b)).foregroundStyle(Theme.fat.opacity(0.22)).cornerRadius(4)
                    }
                    if x.eaten > 0 {
                        BarMark(x: .value("Day", x.day, unit: .day), y: .value("Eaten", x.eaten)).foregroundStyle(x.eaten > t.target ? Theme.bad : Theme.emphasis).cornerRadius(4)
                    }
                }
                RuleMark(y: .value("Target", t.target)).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                    .annotation(position: .top, alignment: .trailing) { Text("target \(t.target.kcalString)").font(.caption2).foregroundStyle(.secondary) }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.day(), centered: true).font(.caption2) } }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text(d.kcalString).font(.caption2) } } } }
            .frame(height: 170)
            HStack(spacing: 14) {
                legend(Theme.emphasis, "Eaten"); legend(Theme.fat.opacity(0.35), "Burned (Watch)"); legend(.secondary, "Target")
            }.font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func legend(_ c: Color, _ t: String) -> some View { HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10); Text(t) } }
}
