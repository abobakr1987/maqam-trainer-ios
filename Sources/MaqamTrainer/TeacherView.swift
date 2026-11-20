import SwiftUI
import UIKit

/// The AI teacher («المدرّس»): a virtual teacher persona created by AI.
/// The teacher SINGS each maqam — the scale up/down on "آه", then a short
/// phrase — from bundled audio files in TeacherAudio/ (see manifest.json).
/// If a maqam's audio has not been dropped in yet, the tab says
/// «الدرس الصوتي بيتحضّر» and still shows the teacher's written lesson.
/// No external video or links exist anywhere in this app — all bundled.
struct TeacherView: View {
    @StateObject private var player = TeacherPlayer()
    @State private var selectedMaqam: Maqam = Maqam.all[0]
    private let library = TeacherAudioLibrary()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Teacher avatar slot: asset named "TeacherAvatar".
                // Until a real avatar image is dropped into
                // Assets.xcassets, a drawn placeholder is shown.
                avatar
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.orange, lineWidth: 3))

                Text("مدرّسك الافتراضي")
                    .font(.title3).bold()
                Text("شخصية مدرّس مولّدة بالذكاء الاصطناعي — بيغنّي لك المقام بصوته وتقول وراه.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Picker("المقام", selection: $selectedMaqam) {
                    ForEach(Maqam.all) { maqam in
                        Text(maqam.nameArabic).tag(maqam)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedMaqam) { _ in player.stop() }

                // The teacher's spoken lesson text for this maqam.
                Text(TeacherIntros.text(forMaqamID: selectedMaqam.id))
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(12)

                Text(selectedMaqam.degreeNames.joined(separator: " · "))
                    .font(.callout)
                    .foregroundColor(.secondary)

                lessonButton(kind: .scale,
                             title: "🎤 المدرّس بيغنّي السلّم — اسمع وقول وراه")
                lessonButton(kind: .phrase,
                             title: "🎵 جملة بالمقام بصوت المدرّس")

                if player.isPlaying {
                    Button("⏹ وقّف") { player.stop() }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("المدرّس")
        .onDisappear { player.stop() }
    }

    @ViewBuilder
    private var avatar: some View {
        if let image = UIImage(named: "TeacherAvatar") {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color.orange.opacity(0.2)
                Image(systemName: "person.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.orange)
            }
        }
    }

    @ViewBuilder
    private func lessonButton(kind: TeacherAudioKind, title: String) -> some View {
        if let url = library.url(forMaqamID: selectedMaqam.id, kind: kind) {
            Button(player.isPlaying && player.currentKind == kind ? "🔊 شغّال دلوقتي…" : title) {
                player.play(url: url, kind: kind)
            }
            .buttonStyle(.borderedProminent)
            .disabled(player.isPlaying)
        } else {
            VStack(spacing: 4) {
                Text(title)
                    .font(.callout)
                    .foregroundColor(.secondary)
                Text("الدرس الصوتي بيتحضّر")
                    .font(.headline)
                    .foregroundColor(.orange)
            }
            .padding(.vertical, 6)
        }
    }
}
