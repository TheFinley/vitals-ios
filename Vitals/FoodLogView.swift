import SwiftUI
import SwiftData
import PhotosUI

struct FoodLogView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthKitManager.self) private var health
    @Environment(ProfileStore.self) private var profileStore
    @Query(sort: \Meal.time) private var allMeals: [Meal]

    @State private var day = Date.now.startOfDay
    @State private var describeText = ""
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var review: ReviewRequest?
    @State private var showLibrary = false
    @State private var showBarcode = false

    private var meals: [Meal] { allMeals.filter { $0.day == day } }
    private var totals: Totals { meals.map(\.totals).reduce(.zero, +) }
    private var targets: Targets { profileStore.targets(watchTDEE: health.watchTDEE30) }
    private var burned: (value: Double, source: String) {
        if let b = health.burnedByDay[day] { return (b, "Apple Watch") }
        return (targets.tdee, "estimate")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    dayStrip
                    logCard
                    calorieCard
                    mealsCard
                    nutrientsCard
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Food")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in
                    showCamera = false
                    if let img { review = ReviewRequest(kind: .photo(img), slot: .forHour(Calendar.current.component(.hour, from: .now)), hint: describeText) }
                    describeText = ""
                }.ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        review = ReviewRequest(kind: .photo(img), slot: .forHour(Calendar.current.component(.hour, from: .now)), hint: describeText)
                        describeText = ""
                    }
                    photoItem = nil
                }
            }
            .photosPicker(isPresented: $showLibrary, selection: $photoItem, matching: .images)
            .sheet(isPresented: $showBarcode) {
                BarcodeScannerSheet { code in review = ReviewRequest(kind: .barcode(code), slot: .forHour(Calendar.current.component(.hour, from: .now)), hint: "") }
            }
            .sheet(item: $review) { req in
                MealReviewView(request: req, day: day)
            }
        }
    }

    // MARK: Sections

    private var dayStrip: some View {
        HStack {
            Button { day = day.adding(days: -1) } label: { Image(systemName: "chevron.left").frame(width: 34, height: 34) }
                .background(Color(.secondarySystemGroupedBackground), in: Circle())
            Spacer()
            VStack(spacing: 2) {
                Text(day.isToday ? "Today" : Calendar.current.isDateInYesterday(day) ? "Yesterday" : day.formatted(.dateTime.weekday(.wide))).font(.headline)
                Text(day.formatted(.dateTime.day().month(.wide).year())).font(.caption).foregroundStyle(.secondary)
                if !day.isToday { Button("Jump to today") { day = .now.startOfDay }.font(.caption2).fontWeight(.bold) }
            }
            Spacer()
            Button { day = day.adding(days: 1) } label: { Image(systemName: "chevron.right").frame(width: 34, height: 34) }
                .background(Color(.secondarySystemGroupedBackground), in: Circle())
                .disabled(day.isToday).opacity(day.isToday ? 0.35 : 1)
        }
        .padding(.top, 4)
    }

    private var logCard: some View {
        Card(title: "Log a meal", subtitle: ClaudeService.shared.hasKey ? "Claude-enhanced estimates" : "Free · on-device + USDA", symbol: "camera") {
            HStack(spacing: 10) {
                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true } else { showLibrary = true }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "camera.fill").font(.title2)
                        Text("Scan what you're eating").font(.subheadline).fontWeight(.bold)
                        Text("Photo · barcodes detected too").font(.caption2).opacity(0.85)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .foregroundStyle(.white)
                    .background(Theme.carbs, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .contextMenu {
                    PhotosPicker(selection: $photoItem, matching: .images) { Label("Choose from library", systemImage: "photo.on.rectangle") }
                }

                VStack(spacing: 10) {
                    Button { showBarcode = true } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "barcode.viewfinder").font(.title3)
                            Text("Scan barcode").font(.caption).fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    Button {
                        review = ReviewRequest(kind: .manual, slot: .forHour(Calendar.current.component(.hour, from: .now)), hint: "")
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "plus").font(.title3)
                            Text("Add manually").font(.caption).fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .foregroundStyle(.primary)
            }
            HStack(spacing: 8) {
                TextField("Or describe it: “2 eggs, toast, a latte”", text: $describeText)
                    .textFieldStyle(.plain).padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .submitLabel(.go).onSubmit(lookup)
                Button(action: lookup) { Label("Look up", systemImage: "sparkles").font(.subheadline).fontWeight(.bold) }
                    .buttonStyle(.borderedProminent).tint(.primary).foregroundStyle(Color(.systemBackground))
                    .disabled(describeText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Pick a photo from your library instead", systemImage: "photo.on.rectangle").font(.caption).fontWeight(.semibold)
            }
            Text(ClaudeService.shared.hasKey
                 ? "Photos and descriptions are analysed by Claude using standard food-composition values; you confirm portions before anything is saved."
                 : "Foods are recognised on your phone and matched to USDA / Open Food Facts composition values — free, no account. Portions start at a typical serving; adjust the grams before saving.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func lookup() {
        let t = describeText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        review = ReviewRequest(kind: .text(String(t.prefix(600))), slot: .forHour(Calendar.current.component(.hour, from: .now)), hint: "")
        describeText = ""
    }

    private var calorieCard: some View {
        let t = targets
        let eaten = totals[safe: .kcal]
        let remain = t.target - eaten
        return Card(title: "Calories", subtitle: "\(profileStore.profile.goal == .lose ? "Deficit" : profileStore.profile.goal == .gain ? "Surplus" : "Maintenance") target · burned via \(burned.source)", symbol: "flame") {
            HStack(spacing: 18) {
                ZStack {
                    Ring(progress: t.target > 0 ? eaten / t.target : 0, color: Theme.emphasis)
                    VStack(spacing: 0) {
                        Text(abs(remain).kcalString).font(.num(26)).monospacedDigit().foregroundStyle(remain < 0 ? Theme.bad : .primary)
                        Text(remain >= 0 ? "KCAL LEFT" : "KCAL OVER").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary).tracking(0.6)
                    }
                }
                .frame(width: 130, height: 130)
                VStack(spacing: 10) {
                    HStack {
                        kv("Eaten", eaten.kcalString); kv("Target", t.target.kcalString); kv("Burned", burned.value.kcalString)
                    }
                    MacroBar(label: "Protein", value: totals[safe: .protein], target: t.reference[safe: .protein], color: Theme.protein)
                    MacroBar(label: "Carbs", value: totals[safe: .carbs], target: t.reference[safe: .carbs], color: Theme.carbs)
                    MacroBar(label: "Fat", value: totals[safe: .fat], target: t.reference[safe: .fat], color: Theme.fat)
                }
            }
        }
    }
    private func kv(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary).tracking(0.5)
            Text(v).font(.num(15)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mealsCard: some View {
        Card(title: "Meals", subtitle: meals.isEmpty ? "Nothing logged yet" : "\(meals.count) meal\(meals.count == 1 ? "" : "s") · \(totals[safe: .kcal].kcalString) kcal", symbol: "fork.knife") {
            if meals.isEmpty {
                EmptyHint(title: "No meals logged for this day.", text: "Scan a photo, describe what you ate, or add it manually — it takes about ten seconds.")
            } else {
                ForEach(MealSlot.allCases) { slot in
                    let list = meals.filter { $0.slot == slot }
                    if !list.isEmpty {
                        HStack {
                            Label(slot.label.uppercased(), systemImage: slot.symbol).font(.system(size: 11, weight: .heavy)).foregroundStyle(.secondary).tracking(0.6)
                            Spacer()
                            Text("\(list.map { $0.totals[safe: .kcal] }.reduce(0, +).kcalString) kcal").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary).monospacedDigit()
                        }.padding(.top, 4)
                        ForEach(list) { m in
                            Button { review = ReviewRequest(kind: .edit(m), slot: m.slot, hint: "") } label: { MealRow(meal: m) }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var nutrientsCard: some View {
        let t = targets
        let has = totals.values.contains { $0 > 0 }
        return Card(title: "Nutrients vs. reference", subtitle: "Targets tab sets the references", symbol: "drop") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Nutrient.allCases.filter { ![.kcal, .protein, .carbs, .fat].contains($0) }) { n in
                    NutrientTile(nutrient: n, value: totals[safe: n], reference: t.reference[safe: n], hasData: has)
                }
            }
        }
    }
}

struct MealRow: View {
    let meal: Meal
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(.tertiarySystemGroupedBackground))
                if let d = meal.photo, let img = UIImage(data: d) {
                    Image(uiImage: img).resizable().scaledToFill().frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                } else {
                    Image(systemName: meal.source == .text ? "sparkles" : meal.source == .photo ? "camera" : "fork.knife").foregroundStyle(Theme.carbs)
                }
            }.frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.displayName.isEmpty ? "Meal" : meal.displayName).font(.subheadline).fontWeight(.semibold).lineLimit(1)
                let t = meal.totals
                Text("\(meal.time.formatted(date: .omitted, time: .shortened)) · P \(t[safe: .protein].g0) · C \(t[safe: .carbs].g0) · F \(t[safe: .fat].g0) g").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(meal.totals[safe: .kcal].kcalString).font(.num(15)).monospacedDigit()
                Text("kcal").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Review sheet

struct ReviewRequest: Identifiable {
    enum Kind { case photo(UIImage), text(String), barcode(String), manual, edit(Meal) }
    let id = UUID()
    var kind: Kind
    var slot: MealSlot
    var hint: String
}

struct MealReviewView: View {
    let request: ReviewRequest
    let day: Date
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitManager.self) private var health

    @State private var name = ""
    @State private var slot: MealSlot = .lunch
    @State private var time = Date.now
    @State private var items: [FoodItem] = []
    @State private var notes = ""
    @State private var confidence: Double?
    @State private var photo: UIImage?
    @State private var analyzing = false
    @State private var error: String?
    @State private var existing: Meal?
    @State private var confirmDelete = false

    private var totals: Totals { items.totals }

    var body: some View {
        NavigationStack {
            Form {
                if let photo {
                    Section { Image(uiImage: photo).resizable().scaledToFill().frame(height: 200).clipped().listRowInsets(EdgeInsets()) }
                }
                if analyzing {
                    Section { HStack(spacing: 12) { ProgressView(); Text(ClaudeService.shared.hasKey ? (photo != nil ? "Looking at the photo and estimating nutrients… usually 10–30 s." : "Looking up the foods you described…") : "Recognising and looking up nutrients…").font(.subheadline).foregroundStyle(.secondary) } }
                } else if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(Theme.bad) }
                } else if let confidence, !items.isEmpty {
                    Section { Text("\(items.count) item\(items.count == 1 ? "" : "s") found · confidence \(Int(confidence * 100))%\(notes.isEmpty ? "" : " — \(notes)"). Adjust portions or calories before saving.").font(.caption).foregroundStyle(.secondary) }
                }
                Section("Meal") {
                    TextField("Name (e.g. Rice & curry)", text: $name)
                    Picker("Slot", selection: $slot) { ForEach(MealSlot.allCases) { Text($0.label).tag($0) } }
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                }
                Section("Items") {
                    ForEach($items) { $it in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                TextField("Food (e.g. grilled chicken breast)", text: $it.name).fontWeight(.semibold)
                                Button { Task { await lookup(id: it.id) } } label: { Image(systemName: "magnifyingglass").font(.caption).fontWeight(.bold) }
                                    .buttonStyle(.bordered).tint(Theme.carbs)
                            }
                            HStack(spacing: 10) {
                                TextField("Portion (e.g. 1 cup)", text: $it.portion).font(.subheadline).foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                numField("kcal", $it.kcal, width: 60, pad: .numberPad)
                            }
                            HStack(spacing: 8) {
                                numField("g", Binding(get: { it.grams }, set: { rescale(&it, to: $0) }), width: 46, pad: .decimalPad)
                                numField("P", $it.protein, width: 40, pad: .decimalPad)
                                numField("C", $it.carbs, width: 40, pad: .decimalPad)
                                numField("F", $it.fat, width: 40, pad: .decimalPad)
                                Spacer(minLength: 0)
                            }
                            Text("fibre \(it.fiber.g1) · sat fat \(it.satFat.g1) · sugar \(it.sugar.g1) g · sodium \(it.sodium.g0) mg").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    Button { items.append(FoodItem()) } label: { Label("Add item", systemImage: "plus") }
                }
                Section("Totals") {
                    HStack {
                        tot("Calories", totals[safe: .kcal].kcalString, "kcal"); tot("Protein", totals[safe: .protein].g1, "g"); tot("Carbs", totals[safe: .carbs].g1, "g"); tot("Fat", totals[safe: .fat].g1, "g")
                    }
                }
                if existing != nil {
                    Section { Button("Delete meal", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(existing == nil ? "Review meal" : "Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(existing == nil ? "Add to log" : "Save") { save() }.fontWeight(.bold).disabled(analyzing || items.isEmpty) }
            }
            .confirmationDialog("Delete this meal from your log?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteExisting() }
            }
        }
        .task { await start() }
    }

    private func numField(_ label: String, _ value: Binding<Double>, width: CGFloat, pad: UIKeyboardType) -> some View {
        HStack(spacing: 4) {
            TextField("0", value: Binding<Double?>(get: { value.wrappedValue == 0 ? nil : value.wrappedValue }, set: { value.wrappedValue = $0 ?? 0 }), format: .number.precision(.fractionLength(0...1))).keyboardType(pad)
                .multilineTextAlignment(.trailing).monospacedDigit().fontWeight(.semibold).frame(width: width)
                .padding(.horizontal, 5).padding(.vertical, 5)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(label).font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary).fixedSize()
        }
    }
    private func tot(_ k: String, _ v: String, _ u: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            (Text(v).font(.num(15)) + Text(" \(u)").font(.caption2).foregroundStyle(.secondary)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Changing grams scales every nutrient proportionally, so a portion tweak never needs retyping.
    private func rescale(_ it: inout FoodItem, to grams: Double) {
        let old = it.grams
        guard grams > 0, old > 0 else { it.grams = grams; return }
        let f = grams / old
        for n in Nutrient.allCases { it[keyPath: n.keyPath] = ((it[keyPath: n.keyPath] * f) * 10).rounded() / 10 }
        it.grams = grams
        it.portion = "\(Int(grams.rounded())) g"
    }
    private func lookup(id: UUID) async {
        guard let current = items.first(where: { $0.id == id }) else { return }
        guard !current.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let found = await FoodLookup.refresh(item: current), let idx = items.firstIndex(where: { $0.id == current.id }) {
            items[idx] = found
        } else {
            error = "No nutrition data found for “\(current.name)”. Try a simpler name."
        }
    }

    private func start() async {
        slot = request.slot
        switch request.kind {
        case .edit(let m):
            existing = m; name = m.name; slot = m.slot; time = m.time; items = m.items; notes = m.notes; confidence = m.confidence
            if let d = m.photo { photo = UIImage(data: d) }
        case .manual:
            items = [FoodItem()]
        case .photo(let img):
            photo = img
            await analyze(image: img, text: nil)
        case .text(let t):
            await analyze(image: nil, text: t)
        case .barcode(let code):
            analyzing = true
            if let it = await OpenFoodFacts.lookup(barcode: code) {
                items = [it]; name = it.name; confidence = 0.95; notes = "From the product label via Open Food Facts."
            } else {
                items = [FoodItem()]; error = "Barcode \(code) isn't in Open Food Facts yet. Add the item by hand."
            }
            analyzing = false
        }
    }

    private func analyze(image: UIImage?, text: String?) async {
        analyzing = true; error = nil
        // Optional paid path only when the person has added a key; the free path is the default and the fallback.
        if ClaudeService.shared.hasKey {
            do {
                let est = try await ClaudeService.shared.analyze(image: image, text: text, slot: slot, hint: request.hint)
                items = est.items.map(\.foodItem)
                name = String(est.meal_name.prefix(80)); notes = String(est.notes.prefix(200)); confidence = est.confidence
                if items.isEmpty { error = "No food was recognised. Add the items by hand or try another photo."; items = [FoodItem()] }
                analyzing = false
                return
            } catch {
                notes = "Claude lookup failed (\(error.localizedDescription)) — used the free lookup instead."
            }
        }
        let res: FoodLookup.Result
        if let image { res = await FoodLookup.analyzePhoto(image) }
        else { res = await FoodLookup.parseText(text ?? "") }
        items = res.items
        confidence = res.confidence
        if notes.isEmpty { notes = res.notes }
        if items.isEmpty { error = res.notes; items = [FoodItem()] }
        else if name.isEmpty { name = items.prefix(2).map(\.name).joined(separator: " & ") }
        analyzing = false
    }

    private func save() {
        let clean = items.filter { !$0.name.isEmpty || $0.kcal > 0 }
        guard !clean.isEmpty else { return }
        let finalName = name.isEmpty ? clean.prefix(3).map(\.name).joined(separator: ", ") : name
        let meal: Meal
        if let m = existing {
            m.name = finalName; m.slot = slot; m.time = time; m.items = clean; m.notes = notes; m.confidence = confidence
            meal = m
        } else {
            let source: MealSource = switch request.kind { case .photo: .photo; case .text: .text; default: .manual }
            let cal = Calendar.current
            let comps = cal.dateComponents([.hour, .minute], from: time)
            let when = cal.date(bySettingHour: comps.hour ?? 12, minute: comps.minute ?? 0, second: 0, of: day) ?? day
            meal = Meal(day: day, time: when, slot: slot, name: finalName, source: source, items: clean,
                        photo: photo.flatMap { Self.thumb($0).jpegData(compressionQuality: 0.8) }, notes: notes, confidence: confidence)
            context.insert(meal)
        }
        try? context.save()
        Task { await health.write(meal: meal) }
        dismiss()
    }

    private func deleteExisting() {
        guard let m = existing else { return }
        let id = m.id
        context.delete(m)
        try? context.save()
        Task { await health.deleteSamples(mealID: id) }
        dismiss()
    }

    private static func thumb(_ img: UIImage, max: CGFloat = 720) -> UIImage {
        let s = min(1, max / Swift.max(img.size.width, img.size.height))
        guard s < 1 else { return img }
        let size = CGSize(width: img.size.width * s, height: img.size.height * s)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        return UIGraphicsImageRenderer(size: size, format: f).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

// MARK: - Camera

struct CameraPicker: UIViewControllerRepresentable {
    var onPick: (UIImage?) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.cameraCaptureMode = .photo
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage?) -> Void
        init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onPick(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onPick(nil) }
    }
}
