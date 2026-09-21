import Foundation
import SwiftData

// MARK: - Nutrients

/// Every nutrient the app tracks, with the reference-intake rule used to judge it.
enum Nutrient: String, CaseIterable, Codable, Identifiable {
    case kcal, protein, carbs, fat, satFat, fiber, sugar, sodium, cholesterol, potassium, calcium, iron, vitaminC, vitaminD

    var id: String { rawValue }

    enum Kind { case target, min, max }

    var label: String {
        switch self {
        case .kcal: "Calories"; case .protein: "Protein"; case .carbs: "Carbohydrate"; case .fat: "Fat"
        case .satFat: "Saturated fat"; case .fiber: "Fibre"; case .sugar: "Sugar"; case .sodium: "Sodium"
        case .cholesterol: "Cholesterol"; case .potassium: "Potassium"; case .calcium: "Calcium"; case .iron: "Iron"
        case .vitaminC: "Vitamin C"; case .vitaminD: "Vitamin D"
        }
    }
    var unit: String {
        switch self {
        case .kcal: "kcal"
        case .protein, .carbs, .fat, .satFat, .fiber, .sugar: "g"
        case .sodium, .cholesterol, .potassium, .calcium, .iron, .vitaminC: "mg"
        case .vitaminD: "µg"
        }
    }
    var kind: Kind {
        switch self {
        case .kcal, .carbs, .fat: .target
        case .protein, .fiber, .potassium, .calcium, .iron, .vitaminC, .vitaminD: .min
        case .satFat, .sugar, .sodium, .cholesterol: .max
        }
    }
    var keyPath: WritableKeyPath<FoodItem, Double> {
        switch self {
        case .kcal: \.kcal; case .protein: \.protein; case .carbs: \.carbs; case .fat: \.fat
        case .satFat: \.satFat; case .fiber: \.fiber; case .sugar: \.sugar; case .sodium: \.sodium
        case .cholesterol: \.cholesterol; case .potassium: \.potassium; case .calcium: \.calcium
        case .iron: \.iron; case .vitaminC: \.vitaminC; case .vitaminD: \.vitaminD
        }
    }
    /// Field name used in the JSON exchanged with Claude.
    var jsonKey: String {
        switch self {
        case .kcal: "kcal"; case .protein: "protein_g"; case .carbs: "carbs_g"; case .fat: "fat_g"
        case .satFat: "sat_fat_g"; case .fiber: "fiber_g"; case .sugar: "sugar_g"; case .sodium: "sodium_mg"
        case .cholesterol: "cholesterol_mg"; case .potassium: "potassium_mg"; case .calcium: "calcium_mg"
        case .iron: "iron_mg"; case .vitaminC: "vitamin_c_mg"; case .vitaminD: "vitamin_d_ug"
        }
    }
}

typealias Totals = [Nutrient: Double]

extension Dictionary where Key == Nutrient, Value == Double {
    static var zero: Totals { Dictionary(uniqueKeysWithValues: Nutrient.allCases.map { ($0, 0) }) }
    subscript(safe n: Nutrient) -> Double { self[n] ?? 0 }
    static func + (a: Totals, b: Totals) -> Totals {
        var out = a
        for n in Nutrient.allCases { out[n] = a[safe: n] + b[safe: n] }
        return out
    }
}

struct FoodItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var portion = ""
    var grams: Double = 0
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var satFat: Double = 0
    var fiber: Double = 0
    var sugar: Double = 0
    var sodium: Double = 0
    var cholesterol: Double = 0
    var potassium: Double = 0
    var calcium: Double = 0
    var iron: Double = 0
    var vitaminC: Double = 0
    var vitaminD: Double = 0

    var totals: Totals { Dictionary(uniqueKeysWithValues: Nutrient.allCases.map { ($0, self[keyPath: $0.keyPath]) }) }
}

extension Array where Element == FoodItem {
    var totals: Totals { reduce(.zero) { $0 + $1.totals } }
}

// MARK: - Meals

enum MealSlot: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, snack, dinner
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self { case .breakfast: "sunrise.fill"; case .lunch: "fork.knife"; case .snack: "leaf.fill"; case .dinner: "moon.stars.fill" }
    }
    static func forHour(_ h: Int) -> MealSlot {
        switch h { case 4..<11: .breakfast; case 11..<15: .lunch; case 15..<18: .snack; default: .dinner }
    }
}

enum MealSource: String, Codable { case photo, text, manual }

@Model
final class Meal {
    @Attribute(.unique) var id: UUID
    /// Calendar day (start of day) the meal belongs to.
    var day: Date
    var time: Date
    var slotRaw: String
    var name: String
    var sourceRaw: String
    var notes: String
    var confidence: Double?
    var items: [FoodItem]
    @Attribute(.externalStorage) var photo: Data?
    var createdAt: Date

    init(day: Date, time: Date = .now, slot: MealSlot, name: String = "", source: MealSource = .manual, items: [FoodItem] = [], photo: Data? = nil, notes: String = "", confidence: Double? = nil) {
        self.id = UUID()
        self.day = Calendar.current.startOfDay(for: day)
        self.time = time
        self.slotRaw = slot.rawValue
        self.name = name
        self.sourceRaw = source.rawValue
        self.items = items
        self.photo = photo
        self.notes = notes
        self.confidence = confidence
        self.createdAt = .now
    }

    var slot: MealSlot {
        get { MealSlot(rawValue: slotRaw) ?? .snack }
        set { slotRaw = newValue.rawValue }
    }
    var source: MealSource { MealSource(rawValue: sourceRaw) ?? .manual }
    var totals: Totals { items.totals }
    var displayName: String { name.isEmpty ? items.prefix(3).map(\.name).joined(separator: ", ") : name }
}

@Model
final class WeighIn {
    @Attribute(.unique) var day: Date
    var kg: Double
    var source: String
    init(day: Date, kg: Double, source: String = "Vitals") {
        self.day = Calendar.current.startOfDay(for: day)
        self.kg = kg
        self.source = source
    }
}

// MARK: - Profile & targets

enum Sex: String, Codable, CaseIterable, Identifiable { case male, female; var id: String { rawValue } }
enum Goal: String, Codable, CaseIterable, Identifiable {
    case lose, maintain, gain
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}
enum EnergyBasis: String, Codable, CaseIterable, Identifiable {
    case watch, formula
    var id: String { rawValue }
}

struct Profile: Codable, Equatable {
    var weightKg: Double = 80
    var heightCm: Double = 175
    var dob: Date = Calendar.current.date(from: DateComponents(year: 1990, month: 1, day: 1)) ?? .now
    var sex: Sex = .male
    var basis: EnergyBasis = .watch
    var activity: Double = 1.55
    var goal: Goal = .lose
    var rateKgPerWeek: Double = 0.5
    var targetWeightKg: Double = 75
    var proteinPerKg: Double = 1.8
    var hasSeededFromHealth = false

    var age: Int { max(15, Calendar.current.dateComponents([.year], from: dob, to: .now).year ?? 29) }
}

struct Targets {
    var age: Int
    var bmi: Double
    var bmr: Double
    var tdeeFormula: Double
    var tdeeWatch: Double?
    var tdee: Double
    var dailyDelta: Double
    var target: Double
    var floored: Bool
    var floor: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var reference: Totals
    var healthyMin: Double
    var healthyMax: Double
    var weeksToGoal: Double?
    var waterL: Double

    var bmiCategory: (label: String, tone: Tone) {
        switch bmi {
        case ..<18.5: ("Underweight", .info)
        case ..<25: ("Healthy weight", .good)
        case ..<30: ("Overweight", .warn)
        default: ("Obese", .bad)
        }
    }

    static func compute(_ p: Profile, watchTDEE: Double?) -> Targets {
        let hM = p.heightCm / 100
        let bmi = p.weightKg / (hM * hM)
        // Mifflin–St Jeor resting energy expenditure
        let bmr = (10 * p.weightKg + 6.25 * p.heightCm - 5 * Double(p.age) + (p.sex == .female ? -161 : 5)).rounded()
        let tdeeFormula = (bmr * p.activity).rounded()
        let tdee = (p.basis == .watch && watchTDEE != nil) ? watchTDEE! : tdeeFormula
        let dailyDelta = (p.rateKgPerWeek * 7700 / 7).rounded()   // 7,700 kcal per kg of body fat
        var target = tdee
        if p.goal == .lose { target = tdee - dailyDelta }
        if p.goal == .gain { target = tdee + dailyDelta }
        let floor = max(bmr, p.sex == .female ? 1200 : 1500)
        let floored = p.goal == .lose && target < floor
        if floored { target = floor }
        target = target.rounded()
        let proteinG = (p.proteinPerKg * p.weightKg).rounded()
        let fatG = (target * 0.28 / 9).rounded()
        let carbsG = max(0, ((target - proteinG * 4 - fatG * 9) / 4).rounded())
        let f = p.sex == .female
        let ref: Totals = [
            .kcal: target, .protein: proteinG, .carbs: carbsG, .fat: fatG,
            .satFat: (target * 0.10 / 9).rounded(), .fiber: f ? 25 : 38, .sugar: (target * 0.10 / 4).rounded(),
            .sodium: 2300, .cholesterol: 300, .potassium: f ? 2600 : 3400, .calcium: 1000,
            .iron: f ? 18 : 8, .vitaminC: f ? 75 : 90, .vitaminD: 15,
        ]
        var weeks: Double? = nil
        if p.goal != .maintain, p.rateKgPerWeek > 0 { weeks = abs(p.weightKg - p.targetWeightKg) / p.rateKgPerWeek }
        return Targets(age: p.age, bmi: bmi, bmr: bmr, tdeeFormula: tdeeFormula, tdeeWatch: watchTDEE, tdee: tdee,
                       dailyDelta: dailyDelta, target: target, floored: floored, floor: floor,
                       proteinG: proteinG, carbsG: carbsG, fatG: fatG, reference: ref,
                       healthyMin: (18.5 * hM * hM).rounded(), healthyMax: (24.9 * hM * hM).rounded(),
                       weeksToGoal: weeks, waterL: f ? 2.7 : 3.7)
    }
}

enum Tone { case good, warn, bad, info, neutral }

/// How a day's intake of one nutrient compares with its reference value.
func nutrientStatus(_ n: Nutrient, value: Double, reference: Double) -> (tone: Tone, text: String) {
    guard reference > 0 else { return (.neutral, "—") }
    let pct = value / reference * 100
    switch n.kind {
    case .max:
        if pct > 100 { return (.bad, "over") }
        if pct > 80 { return (.warn, "near limit") }
        return (.good, "ok")
    case .min:
        if pct >= 90 { return (.good, "met") }
        if pct >= 50 { return (.warn, "\(Int(pct))%") }
        return (.bad, "\(Int(pct))%")
    case .target:
        if pct > 110 { return (.bad, "over") }
        if pct >= 85 { return (.good, "on target") }
        return (.neutral, "\(Int(pct))%")
    }
}

// MARK: - Profile store

@Observable
final class ProfileStore {
    private static let key = "vitals.profile.v1"
    var profile: Profile {
        didSet { save() }
    }
    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key), let p = try? JSONDecoder().decode(Profile.self, from: data) {
            profile = p
        } else {
            profile = Profile()
        }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(profile) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
    func targets(watchTDEE: Double?) -> Targets { Targets.compute(profile, watchTDEE: watchTDEE) }
}

// MARK: - Formatting helpers

extension Double {
    var kcalString: String { Int(rounded()).formatted() }
    var g1: String { formatted(.number.precision(.fractionLength(0...1))) }
    var g0: String { Int(rounded()).formatted() }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    func adding(days: Int) -> Date { Calendar.current.date(byAdding: .day, value: days, to: self) ?? self }
    var isToday: Bool { Calendar.current.isDateInToday(self) }
}
