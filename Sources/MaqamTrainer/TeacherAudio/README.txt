TeacherAudio — drop-in folder for the AI teacher's sung lessons.

For each maqam, drop two audio files here, named exactly as in
manifest.json:

  <maqam>-scale.m4a   the scale sung up and down on "ah", slow, twice
  <maqam>-phrase.m4a  a short sung phrase ending with a qafla on the tonic

The audio is produced and pitch-verified separately (dry voice, no
autotune, quarter tones exact). No code change is needed when files are
added or replaced — the app reads manifest.json at launch. While a file
is missing, the teacher tab shows «الدرس الصوتي بيتحضّر» and still shows
the written lesson. There is no external/online fallback by design.
