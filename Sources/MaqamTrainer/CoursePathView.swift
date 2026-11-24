import SwiftUI

/// Completion state for the course path, persisted in UserDefaults.
final class CourseProgress: ObservableObject {
    @Published private(set) var completed: Set<String> = []

    private let defaultsKey = "coursepath.completed.v1"

    init() {
        completed = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
    }

    func isDone(_ itemID: String) -> Bool {
        completed.contains(itemID)
    }

    func toggle(_ itemID: String) {
        if completed.contains(itemID) {
            completed.remove(itemID)
        } else {
            completed.insert(itemID)
        }
        UserDefaults.standard.set(Array(completed), forKey: defaultsKey)
    }
}

/// Where a course item takes the user when tapped (besides its checkbox).
enum CourseItemAction {
    case tab(AppTab)
    case none
}

/// One checkable step inside a course stage.
struct CourseItem: Identifiable {
    let id: String
    let title: String
    /// Shown in orange under the title (e.g. «لسه بيتحضّر»).
    var note: String? = nil
    var action: CourseItemAction = .none
    /// False when the content the step needs does not exist yet — the
    /// step is shown honestly with its note and cannot be checked off.
    var available: Bool = true
}

/// One stage of «مسار الإتقان».
struct CourseStage: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let items: [CourseItem]
}

extension CourseStage {
    /// Maqams whose full scale recording is bundled in the teacher tab.
    private static let scaleReadyIDs: Set<String> = ["rast", "bayati", "nahawand", "kurd", "ajam", "hijazkar"]
    /// Maqams whose sung phrase is bundled in the teacher tab.
    private static let phraseReadyIDs: Set<String> = ["hijaz", "nahawand", "saba", "sikah"]

    static func makeStages() -> [CourseStage] {
        // Stage 1 — one item per maqam for its scale.
        let stage1Items: [CourseItem] = Maqam.all.map { maqam in
            if scaleReadyIDs.contains(maqam.id) {
                return CourseItem(
                    id: "s1-scale-\(maqam.id)",
                    title: "اسمع سلّم \(maqam.nameArabic) في تبويب المدرّس وقوله وراه صعودًا ونزولًا",
                    action: .tab(.teacher))
            }
            return CourseItem(
                id: "s1-scale-\(maqam.id)",
                title: "اسمع سلّم \(maqam.nameArabic) في تبويب المدرّس وقوله وراه",
                note: "سلّم \(maqam.nameArabic) لسه بيتحضّر — اسمع جملته في المرحلة التانية دلوقتي",
                action: .tab(.teacher),
                available: false)
        }

        // Stage 2 — one item per bundled phrase.
        let stage2Items: [CourseItem] = Maqam.all
            .filter { phraseReadyIDs.contains($0.id) }
            .map { maqam in
                CourseItem(
                    id: "s2-phrase-\(maqam.id)",
                    title: "اسمع جملة \(maqam.nameArabic) بصوت المدرّس ولاحظ الجنس والقفلة",
                    action: .tab(.teacher))
            }

        return [
            CourseStage(
                id: "stage1",
                title: "المرحلة ١: سماع السلالم وتمييزها",
                subtitle: "ودنك تتعود على كل مقام من تسجيله الحقيقي قبل ما تغنّيه.",
                items: stage1Items),
            CourseStage(
                id: "stage2",
                title: "المرحلة ٢: الأجناس والعبارات",
                subtitle: "المقام مش سلّم بس — اسمع الجمل الجاهزة وحسّ بطعم كل جنس.",
                items: stage2Items),
            CourseStage(
                id: "stage3",
                title: "المرحلة ٣: التدريب الصوتي بالمدرّب",
                subtitle: "هنا دور صوتك انت: المدرب اللايف بيسمعك ويديك درجتك على كل نغمة.",
                items: [
                    CourseItem(
                        id: "s3-guided",
                        title: "اعمل تمرين مقام موجّه كامل في المدرب اللايف",
                        action: .tab(.coach)),
                    CourseItem(
                        id: "s3-hold",
                        title: "تمرين ثبات النغمة: امسك درجة واحدة جوه ±15 سنت أطول وقت تقدر",
                        action: .tab(.coach)),
                    CourseItem(
                        id: "s3-range",
                        title: "قِس مدى صوتك في المدرب واعرف قرارك وجوابك المريح",
                        action: .tab(.coach)),
                    CourseItem(
                        id: "s3-breath",
                        title: "اعمل جلسة تمرين نفَس (من البطاقة اللي فوق) قبل ما تبدأ الغنا",
                        action: .none)
                ]),
            CourseStage(
                id: "stage4",
                title: "المرحلة ٤: الانتقالات",
                subtitle: "اتعلم تعبر من مقام لمقام عند النغمات المشتركة من غير ما تقع.",
                items: [
                    CourseItem(
                        id: "s4-pivot",
                        title: "اسمع النقلات المحورية الست وكرر كل نقلة ورا التسجيل",
                        action: .tab(.transitions)),
                    CourseItem(
                        id: "s4-phrase",
                        title: "اسمع نقلات العبارات الأربع ولاحظ النغمة المشتركة في كل نقلة",
                        action: .tab(.transitions))
                ]),
            CourseStage(
                id: "stage5",
                title: "المرحلة ٥: الدمج وأصعب المقاطع",
                subtitle: "مقامين وتلاتة ورا بعض بأنفاس قصيرة — ده تدريب المحترفين.",
                items: [
                    CourseItem(
                        id: "s5-full",
                        title: "تمرين البياتي كاملًا ثم الراست كاملًا بنفَس قصير بينهم",
                        action: .tab(.transitions)),
                    CourseItem(
                        id: "s5-chain",
                        title: "سلسلة الصعود: راست + بياتي + عجم من غير نزول بينهم",
                        action: .tab(.transitions)),
                    CourseItem(
                        id: "s5-loop",
                        title: "حلقة المحور بياتي ↔ راست: كرر العبور لحد ما يبقى تلقائي",
                        action: .tab(.transitions))
                ]),
            CourseStage(
                id: "stage6",
                title: "المرحلة ٦: الإتقان — غناء حر وتقييم ذاتي",
                subtitle: "من غير مرجع: غنِّ، وبعدين قارن وقيّم نفسك بصراحة.",
                items: [
                    CourseItem(
                        id: "s6-free",
                        title: "غنِّ سلّم مقام من اختيارك كاملًا من غير مرجع، وبعدين قارن بتسجيل المدرّس",
                        action: .tab(.coach)),
                    CourseItem(
                        id: "s6-self",
                        title: "اكتب لنفسك ملاحظة صادقة: أنضف مقام عندك وأصعب درجة، وارجع لها بعد أسبوع",
                        action: .none)
                ])
        ]
    }
}

/// «مسار الإتقان»: a staged curriculum over everything in the app —
/// teacher lessons, the live coach, breathing, transitions and drills —
/// with per-step checkmarks persisted in UserDefaults.
struct CoursePathView: View {
    @EnvironmentObject private var progress: CourseProgress
    @Binding var selectedTab: AppTab

    private let stages = CourseStage.makeStages()

    private var totalAvailable: Int {
        stages.flatMap { $0.items }.filter { $0.available }.count
    }

    private var totalDone: Int {
        stages.flatMap { $0.items }.filter { $0.available && progress.isDone($0.id) }.count
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("أنجزت \(totalDone) من \(totalAvailable) خطوة")
                        .font(.headline)
                    ProgressView(value: Double(totalDone),
                                 total: Double(max(totalAvailable, 1)))
                        .tint(.orange)
                    Text("امشِ بالترتيب: كل مرحلة بتجهزك للي بعدها، وعلّم على كل خطوة أول ما تخلصها بجد.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                NavigationLink {
                    BreathingView()
                } label: {
                    HStack {
                        Text("🫁")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("تمرين النفس").font(.headline)
                            Text("جلسات تنفس موجّهة للمغنيين — ابدأ بيها يومك")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            ForEach(stages) { stage in
                Section(header: stageHeader(stage)) {
                    ForEach(stage.items) { item in
                        itemRow(item)
                    }
                }
            }
        }
        .navigationTitle("مسار الإتقان")
    }

    private func stageHeader(_ stage: CourseStage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stage.title)
            Text(stage.subtitle)
                .font(.footnote)
                .foregroundColor(.secondary)
                .textCase(nil)
        }
    }

    @ViewBuilder
    private func itemRow(_ item: CourseItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                progress.toggle(item.id)
            } label: {
                Image(systemName: progress.isDone(item.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(progress.isDone(item.id) ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!item.available)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.callout)
                    .foregroundColor(item.available ? .primary : .secondary)
                if let note = item.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            if case .tab(let tab) = item.action {
                Button("افتح") {
                    selectedTab = tab
                }
                .font(.callout)
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 2)
    }
}
