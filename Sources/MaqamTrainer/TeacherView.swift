import SwiftUI
import UIKit

/// One maqam's page — the single home for everything about it:
/// the teacher's written lesson, his recorded voice (the scale,
/// then a phrase), a jump into the live coach pre-set to this
/// maqam, and the maqam's own piano keys. Audio comes from the
/// bundled TeacherAudio/ files (see manifest.json); a maqam whose
/// recording has not arrived yet honestly shows «بيتحضّر» instead
/// of any substitute sound. No external video or links exist
/// anywhere in this app — all bundled.
struct MaqamPage: View {
    let maqam: Maqam
    @Binding var selectedTab: AppTab
    @EnvironmentObject private var engine: AudioEngine
    @EnvironmentObject private var appState: AppState
    @StateObject private var player = TeacherPlayer()
    private let library = TeacherAudioLibrary()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 12) {
                    avatar
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.orange, lineWidth: 2))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("مدرّسك")
                            .font(.headline)
                        Text("الدروس مسجّلة بصوت بشري حقيقي — اسمع وقول وراه.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                // The teacher's spoken lesson text for this maqam.
                Text(TeacherIntros.text(forMaqamID: maqam.id))
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(12)

                Text(maqam.degreeNames.joined(separator: " · "))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .environment(\.layoutDirection, .leftToRight)

                Text(maqam.comment)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                lessonButton(kind: .scale,
                             title: "🎤 المدرّس بيغنّي السلّم — اسمع وقول وراه")
                lessonButton(kind: .phrase,
                             title: "🎵 جملة بالمقام بصوت المدرّس")

                if player.isPlaying {
                    Button("⏹ وقّف") { player.stop() }
                        .buttonStyle(.bordered)
                }

                Divider()
                    .padding(.top, 4)

                Button {
                    appState.coachMaqamID = maqam.id
                    selectedTab = .coach
                } label: {
                    Label("درّب المقام ده مع المدرب اللايف", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Divider()

                pianoStrip
            }
            .padding()
        }
        .navigationTitle(maqam.nameArabic)
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
                    .font(.system(size: 26))
                    .foregroundColor(.orange)
            }
        }
    }

    @ViewBuilder
    private func lessonButton(kind: TeacherAudioKind, title: String) -> some View {
        if let url = library.url(forMaqamID: maqam.id, kind: kind) {
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

    /// This maqam's degrees as tappable piano keys, quarter-tone
    /// exact — the same keys as the piano tab, but for this maqam
    /// only, right here on its page.
    private var pianoStrip: some View {
        VStack(spacing: 12) {
            Text("🎹 درجاته على البيانو")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(Array(maqam.scaleCents.enumerated()), id: \.offset) { index, cents in
                    Button {
                        engine.playTone(frequency: maqam.frequency(forDegree: index),
                                        duration: 0.7)
                    } label: {
                        VStack {
                            Spacer()
                            Text(maqam.noteName(forDegree: index))
                                .font(.caption2)
                                .foregroundColor(.black)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .background(cents % 100 == 50 ? Color.yellow.opacity(0.55) : Color.white)
                        .border(Color.black.opacity(0.6), width: 1)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("🔊 اسمع السلّم كامل على البيانو") {
                engine.playScale(of: maqam)
            }
            .buttonStyle(.bordered)
        }
    }
}
