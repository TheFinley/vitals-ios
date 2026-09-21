import Foundation
import HealthKit

struct DaySummary {
    var steps: Double = 0
    var activeKcal: Double = 0
    var basalKcal: Double = 0
    var exerciseMin: Double = 0
    var restingHR: Double?
    var sleepHours: Double?
    var burned: Double? { (activeKcal > 0 && basalKcal > 0) ? activeKcal + basalKcal : nil }
}

/// Reads activity, energy, heart and body metrics from Apple Health and writes
/// logged meals and weigh-ins back, so the Health app stays the single record.
@MainActor
@Observable
final class HealthKitManager {
    let store = HKHealthStore()
    let isAvailable = HKHealthStore.isHealthDataAvailable()
    var authorizationRequested = false
    var today = DaySummary()
    /// Total energy (active + basal) per day for the last 30 days, keyed by start of day.
    var burnedByDay: [Date: Double] = [:]
    var stepsByDay: [Date: Double] = [:]
    var watchTDEE30: Double?
    var latestWeightKg: Double?
    var latestHeightCm: Double?
    var dateOfBirth: Date?
    var biologicalSex: Sex?
    var lastRefresh: Date?

    private var readTypes: Set<HKObjectType> {
        let quantities: [HKQuantityTypeIdentifier] = [.stepCount, .activeEnergyBurned, .basalEnergyBurned, .appleExerciseTime, .restingHeartRate, .bodyMass, .height]
        var s = Set<HKObjectType>(quantities.map { HKQuantityType($0) as HKObjectType })
        s.insert(HKCategoryType(.sleepAnalysis) as HKObjectType)
        s.insert(HKCharacteristicType(.dateOfBirth) as HKObjectType)
        s.insert(HKCharacteristicType(.biologicalSex) as HKObjectType)
        s.formUnion(Self.dietaryTypes.values.map { $0 as HKObjectType })
        return s
    }
    private var writeTypes: Set<HKSampleType> {
        var s = Set<HKSampleType>(Self.dietaryTypes.values.map { $0 as HKSampleType })
        s.insert(HKQuantityType(.bodyMass) as HKSampleType)
        return s
    }

    static let dietaryTypes: [Nutrient: HKQuantityType] = [
        .kcal: HKQuantityType(.dietaryEnergyConsumed), .protein: HKQuantityType(.dietaryProtein),
        .carbs: HKQuantityType(.dietaryCarbohydrates), .fat: HKQuantityType(.dietaryFatTotal),
        .satFat: HKQuantityType(.dietaryFatSaturated), .fiber: HKQuantityType(.dietaryFiber),
        .sugar: HKQuantityType(.dietarySugar), .sodium: HKQuantityType(.dietarySodium),
        .cholesterol: HKQuantityType(.dietaryCholesterol), .potassium: HKQuantityType(.dietaryPotassium),
        .calcium: HKQuantityType(.dietaryCalcium), .iron: HKQuantityType(.dietaryIron),
        .vitaminC: HKQuantityType(.dietaryVitaminC), .vitaminD: HKQuantityType(.dietaryVitaminD),
    ]
    static func hkUnit(for n: Nutrient) -> HKUnit {
        switch n.unit {
        case "kcal": .kilocalorie()
        case "g": .gram()
        case "mg": .gramUnit(with: .milli)
        default: .gramUnit(with: .micro)
        }
    }

    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            authorizationRequested = true
            await refresh()
        } catch {
            print("HealthKit authorization failed: \(error)")
        }
    }

    func refresh() async {
        guard isAvailable else { return }
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: .now)
        let from30 = todayStart.adding(days: -29)

        async let steps = dailySums(.stepCount, unit: .count(), from: from30)
        async let active = dailySums(.activeEnergyBurned, unit: .kilocalorie(), from: from30)
        async let basal = dailySums(.basalEnergyBurned, unit: .kilocalorie(), from: from30)
        async let exercise = dailySums(.appleExerciseTime, unit: .minute(), from: todayStart)
        async let rhr = latestQuantity(.restingHeartRate, unit: .count().unitDivided(by: .minute()), since: todayStart.adding(days: -2))
        async let weight = latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo), since: nil)
        async let height = latestQuantity(.height, unit: .meterUnit(with: .centi), since: nil)
        async let sleep = lastNightSleepHours()

        let (s, a, b, e, r, w, h, sl) = await (steps, active, basal, exercise, rhr, weight, height, sleep)
        stepsByDay = s
        var burned: [Date: Double] = [:]
        for (day, av) in a { if let bv = b[day], av > 0, bv > 0 { burned[day] = av + bv } }
        burnedByDay = burned
        let vals = burned.values.filter { $0 > 800 }
        watchTDEE30 = vals.count >= 7 ? (vals.reduce(0, +) / Double(vals.count)).rounded() : nil
        today = DaySummary(steps: s[todayStart] ?? 0, activeKcal: a[todayStart] ?? 0, basalKcal: b[todayStart] ?? 0,
                           exerciseMin: e[todayStart] ?? 0, restingHR: r, sleepHours: sl)
        latestWeightKg = w
        latestHeightCm = h
        dateOfBirth = try? store.dateOfBirthComponents().date
        if let sexObj = try? store.biologicalSex() {
            switch sexObj.biologicalSex { case .male: biologicalSex = .male; case .female: biologicalSex = .female; default: biologicalSex = nil }
        }
        lastRefresh = .now
    }

    // MARK: Queries

    private func dailySums(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from: Date) async -> [Date: Double] {
        let type = HKQuantityType(id)
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: from)
        let predicate = HKQuery.predicateForSamples(withStart: from, end: nil, options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum, anchorDate: anchor, intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, results, _ in
                var out: [Date: Double] = [:]
                results?.enumerateStatistics(from: from, to: .now) { stat, _ in
                    if let sum = stat.sumQuantity() { out[cal.startOfDay(for: stat.startDate)] = sum.doubleValue(for: unit) }
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    private func latestQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit, since: Date?) async -> Double? {
        let type = HKQuantityType(id)
        let predicate = since.map { HKQuery.predicateForSamples(withStart: $0, end: nil, options: []) }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let v = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                cont.resume(returning: v)
            }
            store.execute(q)
        }
    }

    private func lastNightSleepHours() async -> Double? {
        let type = HKCategoryType(.sleepAnalysis)
        let start = Calendar.current.startOfDay(for: .now).adding(days: -1).addingTimeInterval(18 * 3600) // 6pm yesterday
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: [])
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                        HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue]
                let secs = (samples as? [HKCategorySample] ?? []).filter { asleep.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                cont.resume(returning: secs > 0 ? secs / 3600 : nil)
            }
            store.execute(q)
        }
    }

    // MARK: Writes

    /// Writes one sample per nutrient for the meal, tagged with the meal id so a later edit replaces them.
    func write(meal: Meal) async {
        guard isAvailable else { return }
        await deleteSamples(mealID: meal.id)
        let totals = meal.totals
        var samples: [HKQuantitySample] = []
        for (n, type) in Self.dietaryTypes {
            let v = totals[safe: n]
            guard v > 0 else { continue }
            let q = HKQuantity(unit: Self.hkUnit(for: n), doubleValue: v)
            let meta: [String: Any] = [
                HKMetadataKeyFoodType: meal.displayName,
                HKMetadataKeySyncIdentifier: "vitals.meal.\(meal.id.uuidString).\(n.rawValue)",
                HKMetadataKeySyncVersion: Int(Date.now.timeIntervalSince1970),
                "VitalsMealID": meal.id.uuidString,
            ]
            samples.append(HKQuantitySample(type: type, quantity: q, start: meal.time, end: meal.time, metadata: meta))
        }
        guard !samples.isEmpty else { return }
        do { try await store.save(samples) } catch { print("HealthKit meal save failed: \(error)") }
    }

    func deleteSamples(mealID: UUID) async {
        guard isAvailable else { return }
        let predicate = HKQuery.predicateForObjects(withMetadataKey: "VitalsMealID", allowedValues: [mealID.uuidString])
        for type in Self.dietaryTypes.values {
            _ = try? await store.deleteObjects(of: type, predicate: predicate)
        }
    }

    func write(weightKg: Double, on day: Date) async {
        guard isAvailable else { return }
        let when = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? day
        let s = HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: weightKg), start: when, end: when)
        do { try await store.save(s) } catch { print("HealthKit weight save failed: \(error)") }
    }
}
