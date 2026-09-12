import Foundation

/// Bundled reference foods (values per 100 g, USDA / EU composition tables, rounded).
/// Covers everyday foods plus the Portuguese and Sri Lankan dishes the user actually eats,
/// so the free path answers instantly and offline for most meals.
struct RefFood {
    let name: String
    let aliases: [String]
    let defaultGrams: Double
    let portionLabel: String
    let kcal: Double, p: Double, c: Double, f: Double, sf: Double, fib: Double, sug: Double
    let na: Double, chol: Double, k: Double, ca: Double, fe: Double, vc: Double, vd: Double

    func item(grams: Double? = nil) -> FoodItem {
        let g = grams ?? defaultGrams
        let s = g / 100
        return FoodItem(name: name, portion: grams == nil ? portionLabel : "\(Int(g.rounded())) g", grams: g,
                        kcal: (kcal * s).rounded(), protein: r1(p * s), carbs: r1(c * s), fat: r1(f * s), satFat: r1(sf * s),
                        fiber: r1(fib * s), sugar: r1(sug * s), sodium: (na * s).rounded(), cholesterol: (chol * s).rounded(),
                        potassium: (k * s).rounded(), calcium: (ca * s).rounded(), iron: r1(fe * s), vitaminC: r1(vc * s), vitaminD: r1(vd * s))
    }
    private func r1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
}

enum FoodDatabase {
    // swiftlint:disable line_length
    private static func F(_ n: String, _ a: [String], _ g: Double, _ pl: String, _ kcal: Double, _ p: Double, _ c: Double, _ f: Double, _ sf: Double, _ fib: Double, _ sug: Double, _ na: Double, _ chol: Double, _ k: Double, _ ca: Double, _ fe: Double, _ vc: Double, _ vd: Double) -> RefFood {
        RefFood(name: n, aliases: a, defaultGrams: g, portionLabel: pl, kcal: kcal, p: p, c: c, f: f, sf: sf, fib: fib, sug: sug, na: na, chol: chol, k: k, ca: ca, fe: fe, vc: vc, vd: vd)
    }

    static let all: [RefFood] = [
        // fruit
        F("Banana", ["bananas"], 118, "1 medium", 89, 1.1, 22.8, 0.3, 0.1, 2.6, 12.2, 1, 0, 358, 5, 0.3, 8.7, 0),
        F("Apple", ["apples"], 182, "1 medium", 52, 0.3, 13.8, 0.2, 0, 2.4, 10.4, 1, 0, 107, 6, 0.1, 4.6, 0),
        F("Orange", ["oranges", "clementine", "tangerine", "mandarin"], 131, "1 medium", 47, 0.9, 11.8, 0.1, 0, 2.4, 9.4, 0, 0, 181, 40, 0.1, 53, 0),
        F("Mango", ["mangoes"], 165, "1 cup, sliced", 60, 0.8, 15, 0.4, 0.1, 1.6, 13.7, 1, 0, 168, 11, 0.2, 36.4, 0),
        F("Papaya", ["papaw"], 145, "1 cup", 43, 0.5, 10.8, 0.3, 0.1, 1.7, 7.8, 8, 0, 182, 20, 0.3, 60.9, 0),
        F("Pineapple", [], 165, "1 cup", 50, 0.5, 13, 0.1, 0, 1.4, 9.9, 1, 0, 109, 13, 0.3, 47.8, 0),
        F("Watermelon", ["melon"], 280, "1 wedge", 30, 0.6, 7.6, 0.2, 0, 0.4, 6.2, 1, 0, 112, 7, 0.2, 8.1, 0),
        F("Grapes", ["grape"], 150, "1 cup", 69, 0.7, 18, 0.2, 0.1, 0.9, 15.5, 2, 0, 191, 10, 0.4, 3.2, 0),
        F("Strawberries", ["strawberry", "berries", "blueberries", "raspberries"], 150, "1 cup", 32, 0.7, 7.7, 0.3, 0, 2, 4.9, 1, 0, 153, 16, 0.4, 58.8, 0),
        F("Dates", ["date"], 24, "3 dates", 277, 1.8, 75, 0.2, 0, 6.7, 66, 1, 0, 696, 64, 0.9, 0, 0),
        F("Avocado", [], 100, "½ avocado", 160, 2, 8.5, 14.7, 2.1, 6.7, 0.7, 7, 0, 485, 12, 0.6, 10, 0),
        // eggs & dairy
        F("Egg", ["eggs", "boiled egg", "fried egg", "scrambled egg", "scrambled eggs"], 50, "1 large egg", 155, 12.6, 1.1, 10.6, 3.3, 0, 1.1, 124, 373, 126, 50, 1.2, 0, 2.2),
        F("Omelette", ["omelet"], 120, "2-egg omelette", 154, 11, 1, 12, 4.5, 0, 1, 200, 330, 130, 55, 1.3, 0, 2),
        F("Greek yoghurt", ["greek yogurt", "yogurt", "yoghurt"], 170, "1 pot", 59, 10, 3.6, 0.4, 0.1, 0, 3.2, 36, 5, 141, 110, 0.1, 0, 0),
        F("Skyr", [], 170, "1 pot", 63, 11, 4, 0.2, 0.1, 0, 4, 40, 3, 150, 120, 0.1, 0, 0),
        F("Cottage cheese", ["queijo fresco", "requeijão"], 150, "1 serving", 98, 11, 3.4, 4.3, 1.7, 0, 2.7, 364, 17, 104, 83, 0.1, 0, 0),
        F("Milk", ["whole milk", "leite", "glass of milk"], 250, "1 glass", 61, 3.2, 4.8, 3.3, 1.9, 0, 5, 43, 10, 132, 113, 0, 0, 0.1),
        F("Cheese", ["cheddar", "queijo", "hard cheese", "gouda"], 30, "1 slice", 403, 23, 1.3, 33, 21, 0, 0.5, 621, 105, 76, 710, 0.1, 0, 0.6),
        F("Butter", ["manteiga"], 10, "1 tsp", 717, 0.9, 0.1, 81, 51, 0, 0.1, 643, 215, 24, 24, 0, 0, 1.5),
        F("Ice cream", ["gelado", "icecream"], 100, "1 scoop", 207, 3.5, 24, 11, 6.8, 0.7, 21, 80, 44, 199, 128, 0.1, 0.6, 0.2),
        // meat, fish
        F("Chicken breast", ["chicken", "grilled chicken", "frango"], 150, "1 breast", 165, 31, 0, 3.6, 1, 0, 0, 74, 85, 256, 15, 1, 0, 0),
        F("Chicken thigh", ["chicken leg", "roast chicken"], 130, "1 thigh", 209, 26, 0, 10.9, 3, 0, 0, 84, 133, 230, 12, 1.3, 0, 0),
        F("Beef steak", ["beef", "steak", "bife"], 150, "1 steak", 250, 26, 0, 15, 6, 0, 0, 72, 90, 318, 18, 2.6, 0, 0.1),
        F("Pork loin", ["pork", "porco", "pork chop"], 150, "1 chop", 242, 27, 0, 14, 5, 0, 0, 62, 80, 423, 6, 0.9, 0, 0.5),
        F("Lamb", ["mutton"], 150, "1 serving", 258, 25, 0, 17, 7, 0, 0, 72, 96, 310, 17, 1.9, 0, 0),
        F("Bacon", [], 30, "2 rashers", 541, 37, 1.4, 42, 14, 0, 0, 1717, 110, 565, 11, 1.4, 0, 0.5),
        F("Chouriço", ["chorizo", "sausage", "sausages"], 60, "1 sausage", 455, 24, 2, 38, 14, 0, 0, 1200, 90, 400, 20, 1.5, 0, 1),
        F("Ham", ["fiambre", "presunto"], 40, "2 slices", 145, 21, 1.5, 6, 2, 0, 1, 1200, 55, 300, 8, 1, 0, 0.5),
        F("Salmon", ["salmão"], 150, "1 fillet", 206, 22, 0, 12, 2.5, 0, 0, 61, 63, 384, 15, 0.3, 0, 13.1),
        F("Grilled sardines", ["sardines", "sardinhas", "sardine"], 150, "3 sardines", 200, 25, 0, 11, 2.8, 0, 0, 100, 120, 400, 380, 2.5, 0, 4),
        F("Mackerel", ["carapau", "cavala"], 150, "1 fillet", 262, 24, 0, 18, 4.2, 0, 0, 94, 75, 401, 15, 1.6, 0.4, 16),
        F("Sea bream", ["dourada", "robalo", "sea bass", "white fish", "fish", "peixe"], 200, "1 fish", 130, 22, 0, 4.5, 1, 0, 0, 80, 60, 350, 20, 0.5, 0, 5),
        F("Bacalhau", ["cod", "salt cod", "bacalao"], 150, "1 serving", 105, 23, 0, 0.9, 0.2, 0, 0, 500, 55, 468, 18, 0.5, 1, 1.4),
        F("Tuna (canned)", ["tuna", "atum"], 100, "1 tin", 116, 25.5, 0, 0.8, 0.2, 0, 0, 320, 42, 237, 11, 1.5, 0, 1.7),
        F("Shrimp", ["prawns", "prawn", "camarão", "camarões"], 100, "1 serving", 99, 24, 0.2, 0.3, 0.1, 0, 0, 111, 189, 259, 70, 0.5, 0, 0),
        F("Octopus", ["polvo"], 150, "1 serving", 164, 30, 4.4, 2, 0.5, 0, 0, 460, 96, 630, 106, 9.5, 8, 0),
        F("Fried squid", ["squid", "calamari", "lulas"], 150, "1 serving", 175, 15, 8, 7.5, 1.9, 0, 0, 260, 220, 250, 30, 0.9, 4, 0),
        F("Tofu", [], 120, "1 serving", 144, 17.3, 2.8, 8.7, 1.3, 2.3, 0.6, 14, 0, 237, 683, 2.7, 0, 0),
        // grains, starches
        F("White rice", ["rice", "arroz", "basmati", "jasmine rice", "steamed rice"], 200, "1 cup, cooked", 130, 2.7, 28.2, 0.3, 0.1, 0.4, 0.1, 1, 0, 35, 10, 1.2, 0, 0),
        F("Brown rice", ["red rice", "wholegrain rice"], 200, "1 cup, cooked", 123, 2.7, 25.6, 1, 0.2, 1.6, 0.2, 4, 0, 86, 3, 0.6, 0, 0),
        F("Fried rice", ["nasi goreng", "egg fried rice"], 250, "1 plate", 163, 4.5, 26, 4.5, 1, 1, 1, 400, 30, 100, 20, 1, 3, 0),
        F("Pasta", ["spaghetti", "penne", "noodles", "macaroni", "massa"], 200, "1 plate, cooked", 158, 5.8, 31, 0.9, 0.2, 1.8, 0.6, 1, 0, 44, 7, 0.5, 0, 0),
        F("Instant noodles", ["ramen", "maggi"], 85, "1 packet", 440, 9.5, 63, 17, 8, 2, 2, 1800, 0, 150, 20, 2.5, 0, 0),
        F("White bread", ["bread", "pão", "toast", "bread roll", "baguette", "slice of bread"], 30, "1 slice", 265, 9, 49, 3.2, 0.7, 2.7, 5, 490, 0, 115, 150, 3.6, 0, 0),
        F("Wholegrain bread", ["whole wheat bread", "brown bread", "pão integral"], 30, "1 slice", 247, 13, 41, 3.4, 0.7, 6, 6, 455, 0, 250, 160, 2.5, 0, 0),
        F("Oats", ["oatmeal", "porridge", "aveia"], 40, "½ cup, dry", 389, 16.9, 66, 6.9, 1.2, 10.6, 1, 2, 0, 429, 54, 4.7, 0, 0),
        F("Granola", ["muesli"], 50, "½ cup", 471, 10, 64, 20, 4, 7, 20, 20, 0, 400, 60, 3, 0, 0),
        F("Cornflakes", ["cereal", "breakfast cereal"], 30, "1 bowl", 357, 7.5, 84, 0.4, 0.1, 3, 8, 729, 0, 168, 5, 8, 20, 3.3),
        F("Potato", ["potatoes", "boiled potatoes", "batata", "mashed potato"], 150, "1 medium", 87, 1.9, 20, 0.1, 0, 1.8, 0.9, 4, 0, 379, 5, 0.3, 13, 0),
        F("French fries", ["fries", "chips", "batatas fritas"], 120, "1 serving", 312, 3.4, 41, 15, 2.3, 3.8, 0.3, 210, 0, 579, 12, 0.8, 4, 0),
        F("Sweet potato", ["batata doce"], 150, "1 medium", 90, 2, 20.7, 0.2, 0, 3.3, 6.5, 36, 0, 475, 38, 0.7, 19.6, 0),
        F("Quinoa", [], 185, "1 cup, cooked", 120, 4.4, 21, 1.9, 0.2, 2.8, 0.9, 7, 0, 172, 17, 1.5, 0, 0),
        F("Couscous", [], 160, "1 cup, cooked", 112, 3.8, 23, 0.2, 0, 1.4, 0.1, 5, 0, 58, 8, 0.4, 0, 0),
        F("Tortilla wrap", ["wrap", "tortilla", "flatbread"], 60, "1 wrap", 310, 8, 51, 8, 3, 3, 2, 600, 0, 150, 100, 3, 0, 0),
        // legumes
        F("Lentils", ["lentil", "lentilhas"], 150, "1 cup, cooked", 116, 9, 20, 0.4, 0.1, 7.9, 1.8, 2, 0, 369, 19, 3.3, 1.5, 0),
        F("Dhal curry", ["dhal", "dal", "parippu", "lentil curry"], 200, "1 bowl", 150, 8, 18, 5.5, 3.5, 6, 1.5, 300, 0, 320, 30, 3, 2, 0),
        F("Chickpeas", ["chickpea", "grão", "garbanzo"], 150, "1 cup, cooked", 164, 8.9, 27.4, 2.6, 0.3, 7.6, 4.8, 7, 0, 291, 49, 2.9, 1.3, 0),
        F("Black beans", ["beans", "kidney beans", "feijão"], 150, "1 cup, cooked", 132, 8.9, 23.7, 0.5, 0.1, 8.7, 0.3, 1, 0, 355, 27, 2.1, 0, 0),
        F("Hummus", [], 60, "¼ cup", 166, 7.9, 14.3, 9.6, 1.4, 6, 0.3, 379, 0, 228, 38, 2.4, 0, 0),
        // Sri Lankan
        F("Rice & curry plate", ["rice and curry", "rice & curry", "curry plate"], 450, "1 plate", 150, 6, 22, 4.5, 2.5, 2, 1, 350, 15, 180, 25, 1.3, 4, 0.2),
        F("Chicken curry", ["curry", "kukul mas curry"], 200, "1 bowl", 180, 15, 5, 11, 6, 1, 2, 450, 55, 300, 30, 1.5, 3, 0),
        F("Fish curry", ["malu curry", "ambul thiyal"], 200, "1 bowl", 140, 16, 5, 6, 3.5, 1, 2, 500, 45, 350, 40, 1, 3, 3),
        F("Pol sambol", ["coconut sambol", "sambol"], 40, "2 tbsp", 350, 3.5, 12, 33, 29, 9, 3, 500, 0, 350, 15, 2, 5, 0),
        F("Kottu roti", ["kottu", "kothu"], 350, "1 plate", 200, 9, 22, 8.5, 3, 1.5, 2, 550, 50, 200, 40, 1.5, 4, 0),
        F("Hopper", ["hoppers", "appa", "egg hopper"], 60, "1 hopper", 200, 4, 33, 5.5, 4.5, 1, 2, 250, 0, 100, 10, 1, 0, 0),
        F("String hoppers", ["string hopper", "idiyappam"], 40, "1 string hopper", 150, 3, 33, 0.5, 0.1, 1, 0, 200, 0, 40, 10, 0.8, 0, 0),
        F("Roti", ["paratha", "godamba roti", "chapati", "naan"], 80, "1 roti", 300, 7, 42, 11, 4, 2, 2, 400, 0, 120, 20, 2, 0, 0),
        F("Coconut milk", ["santan"], 60, "¼ cup", 197, 2, 2.8, 21, 18.9, 0, 0, 13, 0, 220, 18, 1.6, 1, 0),
        F("Milk tea", ["tea with milk", "kiri te", "chai"], 200, "1 cup", 60, 1.5, 10, 1.5, 1, 0, 9, 20, 5, 60, 50, 0, 0, 0),
        // Portuguese
        F("Pastel de nata", ["pastéis de nata", "custard tart", "nata"], 65, "1 tart", 300, 6, 35, 15, 8, 0.8, 18, 150, 90, 100, 60, 0.6, 0, 0.7),
        F("Croissant", [], 60, "1 croissant", 406, 8.2, 45.8, 21, 11.7, 2.6, 11.3, 470, 67, 118, 37, 2, 0, 0),
        F("Bifana", ["pork sandwich"], 200, "1 bifana", 280, 16, 30, 10, 3.5, 1.5, 2, 600, 45, 250, 40, 1.8, 2, 0.3),
        F("Francesinha", [], 500, "1 francesinha", 260, 14, 15, 16, 7, 1, 3, 700, 60, 250, 150, 1.5, 2, 0.5),
        F("Caldo verde", ["kale soup"], 300, "1 bowl", 60, 2, 8, 2.5, 0.6, 1.5, 1, 350, 5, 200, 30, 0.5, 8, 0),
        F("Vegetable soup", ["soup", "sopa", "broth"], 300, "1 bowl", 45, 1.5, 7, 1.2, 0.3, 1.5, 2, 350, 0, 200, 20, 0.5, 5, 0),
        F("Cake", ["bolo", "sponge cake", "slice of cake"], 80, "1 slice", 350, 5, 50, 15, 7, 1, 30, 300, 60, 100, 50, 1, 0, 0.3),
        F("Pudding", ["custard", "pudim", "flan"], 120, "1 serving", 120, 3.5, 20, 3, 1.8, 0, 17, 60, 40, 150, 100, 0.1, 0, 0.3),
        // fast food & composite
        F("Pizza", ["pizza slice"], 107, "1 slice", 266, 11, 33, 10, 4.5, 2.3, 3.6, 598, 17, 172, 188, 2.5, 1, 0),
        F("Burger", ["hamburger", "cheeseburger"], 220, "1 burger", 254, 13, 22, 12, 4.5, 1, 4, 500, 40, 200, 100, 2.5, 1, 0.2),
        F("Ham & cheese sandwich", ["sandwich", "sandes", "tosta mista", "toastie"], 150, "1 sandwich", 250, 13, 24, 11, 5, 1.5, 3, 650, 35, 180, 200, 1.5, 1, 0.3),
        F("Chicken wrap", ["shawarma", "kebab", "doner", "burrito"], 300, "1 wrap", 220, 14, 22, 9, 3, 2, 2, 550, 40, 250, 60, 1.8, 5, 0.2),
        F("Sushi", ["sushi roll", "maki"], 200, "8 pieces", 150, 6, 28, 1.5, 0.3, 1, 3, 400, 10, 100, 15, 0.8, 1, 1),
        F("Mixed salad", ["salad", "green salad", "salada", "lettuce"], 100, "1 bowl", 17, 1.5, 3, 0.2, 0, 1.5, 1, 20, 0, 250, 40, 1, 15, 0),
        // vegetables
        F("Broccoli", ["brócolos"], 100, "1 cup", 35, 2.4, 7.2, 0.4, 0.1, 3.3, 1.4, 41, 0, 293, 40, 0.7, 65, 0),
        F("Spinach", ["espinafres", "greens", "kale", "gotukola", "mallung"], 100, "1 cup, cooked", 23, 3, 3.8, 0.3, 0, 2.4, 0.4, 70, 0, 466, 136, 3.6, 9.8, 0),
        F("Tomato", ["tomatoes", "tomate"], 120, "1 medium", 18, 0.9, 3.9, 0.2, 0, 1.2, 2.6, 5, 0, 237, 10, 0.3, 13.7, 0),
        F("Carrot", ["carrots", "cenoura"], 60, "1 medium", 41, 0.9, 9.6, 0.2, 0, 2.8, 4.7, 69, 0, 320, 33, 0.3, 5.9, 0),
        F("Cucumber", ["pepino"], 100, "½ cucumber", 15, 0.7, 3.6, 0.1, 0, 0.5, 1.7, 2, 0, 147, 16, 0.3, 2.8, 0),
        F("Onion", ["onions", "cebola"], 50, "½ onion", 40, 1.1, 9.3, 0.1, 0, 1.7, 4.2, 4, 0, 146, 23, 0.2, 7.4, 0),
        F("Mixed vegetables", ["vegetables", "veggies", "legumes", "stir fry vegetables"], 150, "1 cup", 50, 2.5, 10, 0.4, 0.1, 3.5, 3, 40, 0, 280, 40, 0.8, 20, 0),
        // fats, nuts, snacks
        F("Olive oil", ["oil", "azeite"], 10, "1 tbsp", 884, 0, 0, 100, 14, 0, 0, 2, 0, 1, 1, 0.6, 0, 0),
        F("Almonds", ["almond", "amêndoas"], 30, "1 handful", 579, 21, 22, 50, 3.8, 12.5, 4.4, 1, 0, 733, 269, 3.7, 0, 0),
        F("Peanuts", ["peanut", "amendoins"], 30, "1 handful", 567, 26, 16, 49, 7, 8.5, 4, 18, 0, 705, 92, 4.6, 0, 0),
        F("Mixed nuts", ["nuts", "cashews", "walnuts"], 30, "1 handful", 607, 20, 21, 54, 8, 7, 4, 300, 0, 600, 100, 3, 0, 0),
        F("Peanut butter", [], 32, "2 tbsp", 588, 25, 20, 50, 10, 6, 9, 430, 0, 650, 50, 1.9, 0, 0),
        F("Crisps", ["potato chips", "chips packet"], 40, "1 small bag", 536, 7, 53, 35, 3.5, 4.8, 0.4, 525, 0, 1275, 24, 1.6, 18, 0),
        F("Popcorn", [], 30, "1 bowl", 387, 12.9, 78, 4.5, 0.6, 14.5, 0.9, 8, 0, 329, 7, 3.2, 0, 0),
        F("Chocolate", ["chocolate bar", "milk chocolate", "dark chocolate"], 40, "1 bar", 535, 7.7, 59, 30, 19, 3.4, 52, 79, 23, 372, 189, 2.4, 0, 0),
        F("Biscuits", ["biscuit", "cookie", "cookies", "bolachas"], 25, "2 biscuits", 480, 5.5, 65, 22, 10, 2, 30, 350, 20, 120, 30, 2, 0, 0),
        F("Honey", ["mel"], 20, "1 tbsp", 304, 0.3, 82, 0, 0, 0.2, 82, 4, 0, 52, 6, 0.4, 0.5, 0),
        F("Sugar", ["açúcar"], 5, "1 tsp", 387, 0, 100, 0, 0, 0, 100, 1, 0, 2, 1, 0, 0, 0),
        F("Whey protein", ["protein shake", "protein powder", "whey"], 30, "1 scoop", 400, 80, 8, 5, 3, 1, 5, 500, 60, 500, 400, 1, 0, 0),
        // drinks
        F("Black coffee", ["coffee", "espresso", "café", "bica", "americano"], 240, "1 cup", 1, 0.1, 0, 0, 0, 0, 0, 2, 0, 49, 2, 0, 0, 0),
        F("Latte", ["galão", "flat white", "coffee with milk", "meia de leite"], 240, "1 cup", 56, 3, 4.5, 3, 1.8, 0, 4.5, 40, 10, 130, 105, 0, 0, 0.1),
        F("Cappuccino", [], 180, "1 cup", 40, 2.5, 3.5, 2, 1.2, 0, 3.5, 30, 8, 100, 80, 0, 0, 0),
        F("Tea", ["green tea", "black tea", "chá", "herbal tea"], 240, "1 cup", 1, 0, 0.3, 0, 0, 0, 0, 3, 0, 37, 0, 0, 0, 0),
        F("Orange juice", ["juice", "sumo", "apple juice", "fruit juice"], 250, "1 glass", 45, 0.7, 10.4, 0.2, 0, 0.2, 8.4, 1, 0, 200, 11, 0.2, 50, 0),
        F("Cola", ["coke", "soda", "soft drink", "fizzy drink", "lemonade"], 330, "1 can", 42, 0, 10.6, 0, 0, 0, 10.6, 4, 0, 2, 2, 0, 0, 0),
        F("Beer", ["cerveja", "lager", "imperial"], 330, "1 bottle", 43, 0.5, 3.6, 0, 0, 0, 0, 4, 0, 27, 4, 0, 0, 0),
        F("Wine", ["red wine", "white wine", "vinho"], 150, "1 glass", 85, 0.1, 2.6, 0, 0, 0, 0.6, 4, 0, 127, 8, 0.5, 0, 0),
        F("Water", ["água", "sparkling water"], 250, "1 glass", 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 10, 0, 0, 0),
    ]
    // swiftlint:enable line_length

    /// Best local match for a free-text name, using a simple token score.
    static func match(_ query: String) -> RefFood? {
        let q = normalize(query)
        guard !q.isEmpty else { return nil }
        var best: (RefFood, Int)? = nil
        for f in all {
            let names = [f.name] + f.aliases
            var score = 0
            for n in names {
                let nn = normalize(n)
                if nn == q { score = max(score, 100) }
                else if q.contains(nn) { score = max(score, 60 + nn.count) }
                else if nn.contains(q) { score = max(score, 40 + q.count) }
                else {
                    let qt = Set(q.split(separator: " ")), nt = Set(nn.split(separator: " "))
                    let common = qt.intersection(nt).count
                    if common > 0 { score = max(score, 20 * common) }
                }
            }
            if score > 0, score > (best?.1 ?? 0) { best = (f, score) }
        }
        return (best?.1 ?? 0) >= 20 ? best?.0 : nil
    }

    static func normalize(_ s: String) -> String {
        var t = s.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        t = t.replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
        // crude singularisation so "eggs" finds "egg"
        let words = t.split(separator: " ").map { w -> String in
            var w = String(w)
            if w.hasSuffix("ies"), w.count > 4 { w = String(w.dropLast(3)) + "y" }
            else if w.hasSuffix("es"), w.count > 4, !w.hasSuffix("ses") { w = String(w.dropLast(2)) }
            else if w.hasSuffix("s"), w.count > 3, !w.hasSuffix("ss") { w = String(w.dropLast()) }
            return w
        }
        return words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}
