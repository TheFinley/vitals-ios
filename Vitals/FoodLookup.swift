import Foundation
import UIKit
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The free path: on-device recognition + public nutrition databases. Nothing here is metered.
///   photo   → Vision classifier → bundled table / USDA FoodData Central
///   barcode → Open Food Facts
///   text    → on-device Apple model (when available) or keyword parsing → bundled table / USDA
enum FoodLookup {
    struct Result { var items: [FoodItem]; var notes: String; var confidence: Double? }

    static let usdaKeyAccount = "usda-api-key"
    static var usdaKey: String { let k = Keychain.read(usdaKeyAccount) ?? ""; return k.isEmpty ? "DEMO_KEY" : k }

    // MARK: Photo

    static func analyzePhoto(_ image: UIImage) async -> Result {
        // 1. A barcode in the frame beats everything — exact label data.
        if let code = detectBarcode(image), let item = await OpenFoodFacts.lookup(barcode: code) {
            return Result(items: [item], notes: "Barcode matched on Open Food Facts", confidence: 0.95)
        }
        // 2. On-device classification.
        let labels = classify(image)
        var items: [FoodItem] = []
        var seen = Set<String>()
        for (label, conf) in labels.prefix(6) where items.count < 3 {
            let key = FoodDatabase.normalize(label)
            if seen.contains(key) { continue }
            if let f = FoodDatabase.match(label) {
                if seen.insert(FoodDatabase.normalize(f.name)).inserted { items.append(f.item()) }
            } else if conf >= 0.25, let it = await USDA.search(label, grams: 100) {
                if seen.insert(FoodDatabase.normalize(it.name)).inserted { items.append(it) }
            }
        }
        if items.isEmpty {
            return Result(items: [], notes: "Couldn't recognise a food in this photo. Type what it is below — the lookup will fill in the nutrients.", confidence: 0)
        }
        let top = labels.first?.1 ?? 0
        return Result(items: items, notes: "Recognised on-device; portions are typical servings — adjust the grams", confidence: Double(top))
    }

    /// Vision's built-in classifier, filtered to things it thinks are food or drink.
    private static func classify(_ image: UIImage) -> [(String, Float)] {
        guard let cg = image.cgImage else { return [] }
        let req = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: cgOrientation(image.imageOrientation), options: [:])
        do { try handler.perform([req]) } catch { return [] }
        let obs = (req.results ?? []).filter { $0.confidence >= 0.08 }
        let junk: Set<String> = ["food", "meal", "dish", "cuisine", "plate", "bowl", "cup", "table", "kitchen", "restaurant", "tableware", "cutlery", "fork", "spoon", "knife", "glass", "mug", "bottle", "snack", "dessert", "breakfast", "lunch", "dinner", "produce", "ingredient", "vegetable", "fruit"]
        return obs.map { ($0.identifier.replacingOccurrences(of: "_", with: " "), $0.confidence) }
            .filter { !junk.contains($0.0) }
            .sorted { $0.1 > $1.1 }
    }

    private static func detectBarcode(_ image: UIImage) -> String? {
        guard let cg = image.cgImage else { return nil }
        let req = VNDetectBarcodesRequest()
        req.symbologies = [.ean13, .ean8, .upce, .code128]
        let handler = VNImageRequestHandler(cgImage: cg, orientation: cgOrientation(image.imageOrientation), options: [:])
        try? handler.perform([req])
        return req.results?.first?.payloadStringValue
    }

    private static func cgOrientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: .up; case .down: .down; case .left: .left; case .right: .right
        case .upMirrored: .upMirrored; case .downMirrored: .downMirrored; case .leftMirrored: .leftMirrored; case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }

    // MARK: Text

    static func parseText(_ text: String) async -> Result {
        // Quantities come from the deterministic parser; the on-device model is only asked to
        // normalise a phrase it couldn't match (it is not reliable about amounts).
        let parts = keywordParse(text)
        var items: [FoodItem] = []
        var missing: [String] = []
        for var p in parts {
            if FoodDatabase.match(p.name) == nil, let norm = await onDeviceNormalize(p.name) {
                if FoodDatabase.match(norm.name) != nil { p.name = norm.name }
                if p.count == nil, let u = norm.units, u != 1 { p.count = u }
            }
            if let f = FoodDatabase.match(p.name) {
                let grams = p.grams ?? (f.defaultGrams * (p.count ?? 1))
                var it = f.item(grams: grams)
                if let c = p.count, p.grams == nil, c != 1 {
                    let unit = f.portionLabel.replacingOccurrences(of: "^1 ", with: "", options: .regularExpression)
                    it.portion = "\(c.g1) × \(unit)"
                }
                items.append(it)
            } else if let it = await USDA.search(p.name, grams: p.grams ?? 100 * (p.count ?? 1)) {
                var it2 = it
                if let c = p.count, c != 1, p.grams == nil { it2.portion = "\(c.g1) × 100 g" }
                items.append(it2)
            } else {
                missing.append(p.name)
            }
        }
        let notes = missing.isEmpty ? "Standard composition values — adjust grams to match your portion" : "No match for: \(missing.joined(separator: ", ")) — add those by hand or rephrase"
        return Result(items: items, notes: notes, confidence: items.isEmpty ? 0 : 0.7)
    }

    /// "2 eggs, toast with butter and a latte" → [(egg, nil, 2), (toast, nil, 1), (butter, nil, 1), (latte, nil, 1)]
    static func keywordParse(_ text: String) -> [(name: String, grams: Double?, count: Double?)] {
        let separators = try! NSRegularExpression(pattern: "\\s*(,|;|\\band\\b|\\bwith\\b|\\+|\\bplus\\b)\\s*", options: .caseInsensitive)
        let s = text.lowercased()
        let pieces = separators.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "|").split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let words: [String: Double] = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "half": 0.5, "some": 1]
        var out: [(String, Double?, Double?)] = []
        for piece in pieces {
            var p = piece
            var grams: Double? = nil, count: Double? = nil
            if let m = p.range(of: "(\\d+(?:[.,]\\d+)?)\\s*(g|gr|grams?|ml)\\b", options: .regularExpression) {
                grams = Double(p[m].replacingOccurrences(of: "[^0-9.,]", with: "", options: .regularExpression).replacingOccurrences(of: ",", with: "."))
                p.removeSubrange(m)
            } else if let m = p.range(of: "^(\\d+(?:[.,]\\d+)?|a|an|one|two|three|four|five|half|some)\\s+", options: .regularExpression) {
                let tok = String(p[m]).trimmingCharacters(in: .whitespaces)
                count = words[tok] ?? Double(tok.replacingOccurrences(of: ",", with: "."))
                p.removeSubrange(m)
            }
            p = p.replacingOccurrences(of: "\\b(of|the|cup|cups|slice|slices|piece|pieces|bowl|glass|large|small|medium)\\b", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            if !p.isEmpty { out.append((p, grams, count)) }
        }
        return out
    }

    /// Apple's on-device language model (iOS 26, Apple Intelligence devices) turns an unmatched
    /// phrase ("the rest of last night's dhal", "bica") into a generic food name. Nil when unavailable.
    private static func onDeviceNormalize(_ phrase: String) async -> (name: String, units: Double?)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            let session = LanguageModelSession(instructions: "Given a short phrase describing something someone ate or drank, reply with the most generic common English food name for it (singular, 1–3 words, e.g. 'egg', 'white bread', 'lentil curry', 'black coffee') and the number of units mentioned (1 when not stated).")
            do {
                let r = try await session.respond(to: phrase, generating: ParsedFood.self)
                let name = r.content.name.trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? nil : (name, r.content.units > 0 ? r.content.units : nil)
            } catch { return nil }
        }
        #endif
        return nil
    }

    static var onDeviceModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { if case .available = SystemLanguageModel.default.availability { return true } }
        #endif
        return false
    }

    /// Coach suggestions from the on-device model. Nil when unavailable.
    static func onDeviceCoach(context: String) async -> [CoachSuggestion]? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            let session = LanguageModelSession(instructions: "You are a pragmatic, evidence-based nutrition coach. Given a person's profile, daily targets and recent food log as JSON, give 5 specific, practical suggestions for the rest of today. Name concrete foods and portions. Each suggestion has a kind (eat, avoid or tip), a title of at most 6 words and a body of at most 30 words.")
            do {
                let r = try await session.respond(to: context, generating: [ParsedSuggestion].self)
                return r.content.map { s in
                    CoachSuggestion(kind: CoachSuggestion.Kind(rawValue: s.kind.lowercased()) ?? .tip, title: s.title, body: s.body)
                }
            } catch { return nil }
        }
        #endif
        return nil
    }

    /// Re-look-up one item by name, keeping the grams the person typed.
    static func refresh(item: FoodItem) async -> FoodItem? {
        let grams = item.grams > 0 ? item.grams : nil
        if let f = FoodDatabase.match(item.name) { var it = f.item(grams: grams); it.id = item.id; return it }
        if var it = await USDA.search(item.name, grams: grams ?? 100) { it.id = item.id; return it }
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct ParsedFood {
    @Guide(description: "Short generic food name in English, singular")
    var name: String
    @Guide(description: "Number of units mentioned, e.g. 2 for '2 eggs'; 1 when not stated")
    var units: Double
}

@available(iOS 26.0, *)
@Generable
struct ParsedSuggestion {
    @Guide(description: "One of: eat, avoid, tip")
    var kind: String
    @Guide(description: "At most 6 words")
    var title: String
    @Guide(description: "At most 30 words")
    var body: String
}
#endif

extension CoachSuggestion {
    init(kind: Kind, title: String, body: String) { self.kind = kind; self.title = title; self.body = body }
}

// MARK: - USDA FoodData Central (free public API)

enum USDA {
    private static let ids: [Nutrient: Int] = [.kcal: 1008, .protein: 1003, .carbs: 1005, .fat: 1004, .satFat: 1258, .fiber: 1079, .sugar: 2000, .sodium: 1093, .cholesterol: 1253, .potassium: 1092, .calcium: 1087, .iron: 1089, .vitaminC: 1162, .vitaminD: 1114]

    static func search(_ query: String, grams: Double) async -> FoodItem? {
        var comps = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        comps.queryItems = [.init(name: "api_key", value: FoodLookup.usdaKey), .init(name: "query", value: query),
                            .init(name: "dataType", value: "Foundation,SR Legacy,Survey (FNDDS)"), .init(name: "pageSize", value: "3")]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url); req.timeoutInterval = 12
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let foods = obj["foods"] as? [[String: Any]], let food = foods.first else { return nil }
        let desc = (food["description"] as? String ?? query).capitalized
        let nutrients = food["foodNutrients"] as? [[String: Any]] ?? []
        var per100: [Nutrient: Double] = [:]
        for n in nutrients {
            guard let id = n["nutrientId"] as? Int, let v = n["value"] as? Double else { continue }
            if let key = ids.first(where: { $0.value == id })?.key { per100[key] = v }
        }
        guard per100[.kcal] != nil || per100[.protein] != nil else { return nil }
        let s = grams / 100
        var it = FoodItem(name: String(desc.prefix(60)), portion: "\(Int(grams.rounded())) g", grams: grams)
        for (n, v) in per100 { it[keyPath: n.keyPath] = ((v * s) * 10).rounded() / 10 }
        return it
    }
}

// MARK: - Open Food Facts (free, packaged foods by barcode)

enum OpenFoodFacts {
    static func lookup(barcode: String) async -> FoodItem? {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=product_name,brands,nutriments,serving_quantity") else { return nil }
        var req = URLRequest(url: url); req.timeoutInterval = 12
        req.setValue("Vitals iOS - personal nutrition tracker", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let product = obj["product"] as? [String: Any], let nut = product["nutriments"] as? [String: Any] else { return nil }
        func v(_ k: String) -> Double { (nut[k] as? Double) ?? Double(nut[k] as? String ?? "") ?? 0 }
        let serving = (product["serving_quantity"] as? Double) ?? Double(product["serving_quantity"] as? String ?? "") ?? 100
        let grams = serving > 0 ? serving : 100
        let s = grams / 100
        let name = [(product["brands"] as? String)?.split(separator: ",").first.map(String.init), product["product_name"] as? String].compactMap { $0 }.joined(separator: " ")
        var kcal = v("energy-kcal_100g"); if kcal == 0 { kcal = v("energy_100g") / 4.184 }
        return FoodItem(name: String(name.isEmpty ? "Packaged food \(barcode)" : name).prefix(60).description, portion: "1 serving (\(Int(grams)) g)", grams: grams,
                        kcal: (kcal * s).rounded(), protein: v("proteins_100g") * s, carbs: v("carbohydrates_100g") * s, fat: v("fat_100g") * s,
                        satFat: v("saturated-fat_100g") * s, fiber: v("fiber_100g") * s, sugar: v("sugars_100g") * s,
                        sodium: v("sodium_100g") * 1000 * s, cholesterol: v("cholesterol_100g") * 1000 * s, potassium: v("potassium_100g") * 1000 * s,
                        calcium: v("calcium_100g") * 1000 * s, iron: v("iron_100g") * 1000 * s, vitaminC: v("vitamin-c_100g") * 1000 * s, vitaminD: v("vitamin-d_100g") * 1_000_000 * s)
    }
}
