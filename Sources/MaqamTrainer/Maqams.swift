import Foundation

/// One maqam: Arabic name, tonic, and its scale as cents offsets from the
/// tonic (100 cents = one semitone, 50 cents = a quarter tone).
/// Note names are produced in English letters (A–G) everywhere, with
/// "half-flat" / "half-sharp" for quarter tones.
struct Maqam: Identifiable, Hashable {
    let id: String
    let nameArabic: String
    /// English tonic name, e.g. "C", "D", "E half-flat", "Bb".
    let tonicName: String
    /// MIDI note number of the tonic's nearest equal-tempered pitch.
    let tonicMidi: Int
    /// Quarter-tone adjustment of the tonic itself, in cents
    /// (only Sikah needs this: its tonic is E half-flat, i.e. -50).
    let tonicAdjustCents: Int
    /// Scale degrees as cents offsets from the tonic, degrees 1...8.
    let scaleCents: [Int]
    /// Short Arabic note about the maqam (variants, character).
    let comment: String

    /// Absolute pitch of the tonic in cents from C0 (MIDI * 100 + adjust).
    var tonicAbsoluteCents: Int { tonicMidi * 100 + tonicAdjustCents }

    /// Tonic frequency in Hz.
    var tonicFrequency: Double {
        let equalTempered = 440.0 * pow(2.0, Double(tonicMidi - 69) / 12.0)
        return equalTempered * pow(2.0, Double(tonicAdjustCents) / 1200.0)
    }

    /// Exact frequency (quarter-tone precise) of a scale degree (0-based).
    func frequency(forDegree index: Int) -> Double {
        tonicFrequency * pow(2.0, Double(scaleCents[index]) / 1200.0)
    }

    /// English note name of a scale degree (0-based).
    func noteName(forDegree index: Int) -> String {
        Self.absoluteNoteName(absoluteCents: tonicAbsoluteCents + scaleCents[index])
    }

    /// English names of all degrees, octave included.
    var degreeNames: [String] { scaleCents.indices.map { noteName(forDegree: $0) } }

    /// English letter name for an absolute pitch given in cents from C0.
    /// Snaps to the nearest 50 cents (quarter tone).
    static func absoluteNoteName(absoluteCents: Int) -> String {
        let wrapped = ((absoluteCents % 1200) + 1200) % 1200
        let snapped = (wrapped + 25) / 50 * 50 % 1200
        switch snapped {
        case 0:    return "C"
        case 50:   return "C half-sharp"
        case 100:  return "C#"
        case 150:  return "D half-flat"
        case 200:  return "D"
        case 250:  return "D half-sharp"
        case 300:  return "D#"
        case 350:  return "E half-flat"
        case 400:  return "E"
        case 450:  return "F half-flat"
        case 500:  return "F"
        case 550:  return "F half-sharp"
        case 600:  return "F#"
        case 650:  return "G half-flat"
        case 700:  return "G"
        case 750:  return "G half-sharp"
        case 800:  return "G#"
        case 850:  return "A half-flat"
        case 900:  return "A"
        case 950:  return "A half-sharp"
        case 1000: return "Bb"
        case 1050: return "B half-flat"
        case 1100: return "B"
        default:   return "C half-flat" // 1150
        }
    }

    /// Arabic gloss for a quarter-tone name, e.g. "E half-flat (نصف بيمول)".
    static func bilingualName(absoluteCents: Int) -> String {
        let name = absoluteNoteName(absoluteCents: absoluteCents)
        if name.contains("half-flat") { return name + " (نصف بيمول)" }
        if name.contains("half-sharp") { return name + " (نصف دييز)" }
        return name
    }
}

extension Maqam {
    static let all: [Maqam] = [
        Maqam(id: "rast", nameArabic: "الراست", tonicName: "C", tonicMidi: 60,
              tonicAdjustCents: 0,
              scaleCents: [0, 200, 350, 500, 700, 900, 1050, 1200],
              comment: "ملك المقامات. جنس الأصل راست على C والركوز على C."),
        Maqam(id: "bayati", nameArabic: "البياتي", tonicName: "D", tonicMidi: 62,
              tonicAdjustCents: 0,
              scaleCents: [0, 150, 300, 500, 700, 850, 1000, 1200],
              comment: "مقام الشجن الأول. جنس الأصل بياتي على D والركوز على D."),
        Maqam(id: "hijaz", nameArabic: "الحجاز", tonicName: "D", tonicMidi: 62,
              tonicAdjustCents: 0,
              scaleCents: [0, 100, 400, 500, 700, 800, 1100, 1200],
              comment: "بعده المميز بين الدرجة الأولى والثانية (100 ثم 400). الركوز على D."),
        Maqam(id: "nahawand", nameArabic: "النهاوند", tonicName: "C", tonicMidi: 60,
              tonicAdjustCents: 0,
              scaleCents: [0, 200, 300, 500, 700, 800, 1100, 1200],
              comment: "قريب من المينور الطبيعي مع سابعة كبيرة عند القفلة. الركوز على C."),
        Maqam(id: "kurd", nameArabic: "الكرد", tonicName: "D", tonicMidi: 62,
              tonicAdjustCents: 0,
              scaleCents: [0, 100, 300, 500, 700, 800, 1000, 1200],
              comment: "هادئ وحزين من غير أرباع تون. الركوز على D."),
        Maqam(id: "saba", nameArabic: "الصبا", tonicName: "D", tonicMidi: 62,
              tonicAdjustCents: 0,
              scaleCents: [0, 150, 300, 400, 700, 800, 1000, 1200],
              comment: "أحزن المقامات؛ رابعته منخفضة (400). الركوز على D."),
        Maqam(id: "sikah", nameArabic: "السيكاه", tonicName: "E half-flat", tonicMidi: 64,
              tonicAdjustCents: -50,
              scaleCents: [0, 150, 400, 500, 650, 850, 1050, 1200],
              comment: "ركوزه نفسه ربع تون: E half-flat. جنس الأصل سيكاه."),
        Maqam(id: "ajam", nameArabic: "العجم", tonicName: "Bb", tonicMidi: 70,
              tonicAdjustCents: 0,
              scaleCents: [0, 200, 400, 500, 700, 900, 1100, 1200],
              comment: "مقابل الماجور الغربي على Bb، من غير أرباع تون."),
        Maqam(id: "hijazkar", nameArabic: "الحجاز كار", tonicName: "C", tonicMidi: 60,
              tonicAdjustCents: 0,
              scaleCents: [0, 100, 400, 500, 700, 800, 1100, 1200],
              comment: "حجاز على C بسابعة كبيرة (1100). تنويعة شائعة: سابعة مرفوعة عند الصعود في الجنس الثاني.")
    ]
}
