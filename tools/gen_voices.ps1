# Generates the enemies' placeholder shouts (English) as WAVs with the
# Windows built-in voice (System.Speech, "Microsoft David"), into
# assets/audio/voice/<id>.wav. The game reads the lines from
# data/ai/shouts.tres; a recording of a real speaker saved under the same
# name replaces a line.
#   powershell -ExecutionPolicy Bypass -File tools/gen_voices.ps1
# The second column is what is said (capitals stress a word).

$lines = @(
    @("spot_1", "Hey! Stop right there!"),
    @("spot_2", "There he is! THERE!"),
    @("spot_3", "POLICE! Police are here!"),
    @("spot_4", "Look out! It's the COPS!"),
    @("threat_1", "Grab him! GRAB HIM!"),
    @("threat_2", "Kill him! KILL HIM!"),
    @("threat_3", "You can't run from us!"),
    @("threat_4", "Come out of there! NOW!"),
    @("threat_5", "I'll find you, cop!"),
    @("melee_1", "I'll CUT you!"),
    @("melee_2", "Come here! Come HERE!"),
    @("grenade_1", "Grenade! Look out!"),
    @("blind_1", "AAH! My eyes!")
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
