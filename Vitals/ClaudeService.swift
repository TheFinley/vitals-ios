import Foundation
import UIKit
import Security

// MARK: - Keychain

enum Keychain {
    private static let service = "com.thefinley.vitals"
    static func read(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func write(_ value: String, account: String) {
        delete(account)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecValueData as String: data,
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(q as CFDictionary, nil)
    }
    static func delete(_ account: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}

// MARK: - DTOs

struct NutritionEstimate: Decodable {
    struct Item: Decodable {
        var name: String
        var portion: String
        var grams: Double
        var kcal: Double
        var protein_g: Double
        var carbs_g: Double
        var fat_g: Double
        var sat_fat_g: Double
        var fiber_g: Double
        var sugar_g: Double
        var sodium_mg: Double
        var cholesterol_mg: Double
        var potassium_mg: Double
        var calcium_mg: Double
        var iron_mg: Double
        var vitamin_c_mg: Double
        var vitamin_d_ug: Double

        var foodItem: FoodItem {
            FoodItem(name: String(name.prefix(80)), portion: String(portion.prefix(60)), grams: grams, kcal: kcal, protein: protein_g, carbs: carbs_g,
                     fat: fat_g, satFat: sat_fat_g, fiber: fiber_g, sugar: sugar_g, sodium: sodium_mg, cholesterol: cholesterol_mg,
                     potassium: potassium_mg, calcium: calcium_mg, iron: iron_mg, vitaminC: vitamin_c_mg, vitaminD: vitamin_d_ug)
        }
    }
    var meal_name: String
    var items: [Item]
    var confidence: Double
    var notes: String
}

struct CoachSuggestion: Decodable, Identifiable {
    enum Kind: String, Decodable { case eat, avoid, tip }
    var id = UUID()
    var kind: Kind
    var title: String
    var body: String
    private enum CodingKeys: String, CodingKey { case kind, title, body }
}

enum ClaudeError: LocalizedError {
    case missingKey, http(Int, String), refusal, badResponse, truncated
    var errorDescription: String? {
        switch self {
        case .missingKey: "Add your Anthropic API key in Settings to enable photo and text lookup."
        case .http(let code, let msg): code == 401 ? "The API key was rejected. Check it in Settings." : code == 429 ? "Rate limited — wait a minute and try again." : "Request failed (\(code)): \(msg)"
        case .refusal: "Claude declined to analyse this request."
        case .badResponse: "The estimate came back in an unexpected shape. Try again or enter the items by hand."
        case .truncated: "The answer was cut short. Try again with a simpler photo or description."
        }
    }
}

// MARK: - Service

/// Raw Messages API client (no official Swift SDK). Uses Claude Opus 5 with structured
/// JSON output so the reply always parses, and server-side refusal fallbacks.
final class ClaudeService {
    static let shared = ClaudeService()
    static let keyAccount = "anthropic-api-key"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-opus-5"

    var hasKey: Bool { !(Keychain.read(Self.keyAccount) ?? "").isEmpty }

    private static let itemSchema: [String: Any] = {
        var props: [String: Any] = ["name": ["type": "string"], "portion": ["type": "string"], "grams": ["type": "number"]]
        for n in Nutrient.allCases { props[n.jsonKey] = ["type": "number"] }
        return ["type": "object", "properties": props, "required": Array(props.keys), "additionalProperties": false]
    }()
    private static let estimateSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "meal_name": ["type": "string"],
            "items": ["type": "array", "items": itemSchema],
            "confidence": ["type": "number"],
            "notes": ["type": "string"],
        ],
        "required": ["meal_name", "items", "confidence", "notes"],
        "additionalProperties": false,
    ]
    private static let coachSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "suggestions": ["type": "array", "items": [
                "type": "object",
                "properties": ["kind": ["type": "string", "enum": ["eat", "avoid", "tip"]], "title": ["type": "string"], "body": ["type": "string"]],
                "required": ["kind", "title", "body"], "additionalProperties": false,
            ]],
        ],
        "required": ["suggestions"], "additionalProperties": false,
    ]

    private static let rules = """
    Rules: one entry per distinct food or drink; "portion" is a short human description like "1 bowl, ~250 g"; every numeric field is a plain number (0 if negligible); use standard food-composition values (USDA / EU tables) scaled to the portion actually present; be realistic about typical restaurant and home portion sizes rather than conservative; "confidence" is 0–1; "notes" is one short sentence on what was uncertain. If there is no food or drink, return an empty items list with confidence 0 and notes "No food detected".
    """

    func analyze(image: UIImage?, text: String?, slot: MealSlot, hint: String = "") async throws -> NutritionEstimate {
        var content: [[String: Any]] = []
        let prompt: String
        if let image {
            guard let jpeg = Self.downsized(image).jpegData(compressionQuality: 0.82) else { throw ClaudeError.badResponse }
            content.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]])
            prompt = "You are a careful nutrition estimator. The attached photo is a \(slot.label.lowercased()) the viewer is about to eat (or just ate). Identify each food and drink visible, estimate the portion from plate/cup size and cutlery for scale, and estimate its nutrition.\n\(hint.isEmpty ? "" : "The viewer added: \"\(hint)\".\n")\(Self.rules)"
        } else {
            prompt = "You are a careful nutrition estimator. The viewer describes a \(slot.label.lowercased()): \"\(text ?? "")\". Interpret quantities as written; when an amount is missing assume a typical single serving. Estimate nutrition for each food and drink.\n\(Self.rules)"
        }
        content.append(["type": "text", "text": prompt])
        let data = try await send(content: content, schema: Self.estimateSchema, effort: image == nil ? "low" : "medium", maxTokens: 4000)
        return try JSONDecoder().decode(NutritionEstimate.self, from: data)
    }

    func coach(context: String) async throws -> [CoachSuggestion] {
        let prompt = "You are a pragmatic, evidence-based nutrition coach. Using the JSON below (a person's profile, daily targets, what they have eaten today and their last 7 logged days), give specific advice for the REST OF TODAY and the coming days. Name concrete foods and portions. Return 5–7 suggestions; each title at most 6 words, each body at most 32 words.\n\n\(context)"
        let data = try await send(content: [["type": "text", "text": prompt]], schema: Self.coachSchema, effort: "medium", maxTokens: 3000)
        struct Wrap: Decodable { var suggestions: [CoachSuggestion] }
        return try JSONDecoder().decode(Wrap.self, from: data).suggestions
    }

    // MARK: HTTP

    private func send(content: [[String: Any]], schema: [String: Any], effort: String, maxTokens: Int) async throws -> Data {
        guard let key = Keychain.read(Self.keyAccount), !key.isEmpty else { throw ClaudeError.missingKey }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "fallbacks": "default",
            "output_config": ["effort": effort, "format": ["type": "json_schema", "schema": schema]],
            "messages": [["role": "user", "content": content]],
        ]
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let msg = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]).flatMap { ($0["error"] as? [String: Any])?["message"] as? String } ?? "unknown error"
            throw ClaudeError.http(code, msg)
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClaudeError.badResponse }
        if obj["stop_reason"] as? String == "refusal" { throw ClaudeError.refusal }
        if obj["stop_reason"] as? String == "max_tokens" { throw ClaudeError.truncated }
        let blocks = obj["content"] as? [[String: Any]] ?? []
        guard let text = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String, let out = text.data(using: .utf8) else { throw ClaudeError.badResponse }
        return out
    }

    private static func downsized(_ img: UIImage, maxSide: CGFloat = 1280) -> UIImage {
        let s = min(1, maxSide / max(img.size.width, img.size.height))
        guard s < 1 else { return img }
        let size = CGSize(width: img.size.width * s, height: img.size.height * s)
        let r = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        return r.image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
