# Generates the enemies' placeholder shouts (Tok Pisin) as WAVs with the
# Windows built-in voice (System.Speech, "Microsoft David"), into
# assets/audio/voice/<id>.wav. The game reads the lines from
# data/ai/shouts.tres; a recording of a real speaker saved under the same
# name replaces a line.
#   powershell -ExecutionPolicy Bypass -File tools/gen_voices.ps1
# The second column is how the line is spelled for an English voice so it
# comes out close to the Tok Pisin.

$lines = @(
    @("spot_1", "Oy! Oy! Sah nup!"),             # Oi, sanap!
    @("spot_2", "Em ee ah! Em ee AH!"),       # Em ia!
    @("spot_3", "POE LEES! Ee come!"),        # Polis i kam!
    @("spot_4", "Look im! Poe lees!"),        # Lukim, polis!
    @("threat_1", "Hoe lim em! Hoe lim EM!"),             # Holim em!
    @("threat_2", "Kill im em! KILL im!"),             # Kilim em!
    @("threat_3", "You no ken run away!"),    # Yu no ken ranawe!
    @("threat_4", "Come out side! NOW!"),          # Kam autsait!
    @("threat_5", "Me buy pine im you!"),     # Mi bai painim yu!
    @("melee_1", "Me buy CUT im you!"),       # Mi bai katim yu!
    @("melee_2", "Come here! Come here!"),    # Kam hia!
    @("grenade_1", "Look out! Bomb!"),        # Lukaut, bom!
    @("blind_1", "AAH! Eye bee long me!")         # Ai bilong mi!
)

Add-Type -AssemblyName System.Speech
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root "assets/audio/voice"
New-Item -ItemType Directory -Force $out | Out-Null
$voice = New-Object System.Speech.Synthesis.SpeechSynthesizer
$voice.SelectVoice("Microsoft David Desktop")
$voice.Rate = 4
$voice.Volume = 100
$format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(22050, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
foreach ($line in $lines) {
    $path = Join-Path $out ($line[0] + ".wav")
    $voice.SetOutputToWaveFile($path, $format)
    # Shouted: raised pitch, fast, full volume, stressed. The game then drives
    # the result into saturation (ShoutBook.drive) so it sounds yelled, not read.
    $ssml = '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="en-US"><prosody pitch="+22%" rate="+25%" volume="x-loud"><emphasis level="strong">' + $line[1] + '</emphasis></prosody></speak>'
    $voice.SpeakSsml($ssml)
    $voice.SetOutputToNull()
    Write-Output ("wrote " + $path)
}
$voice.Dispose()
