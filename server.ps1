param(
    [int]$Port = 3000,
    [string]$HostName = "localhost"
)

$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
$PublicDir = Join-Path $Root "public"
$DataDir = Join-Path $Root ".zhimengshi"
$LegacyDataDir = Join-Path $Root ("." + "ying" + "ci")
$SettingsFile = Join-Path $DataDir "settings-ps.json"
$LegacySettingsFile = Join-Path $LegacyDataDir "settings-ps.json"

$DefaultModels = @{
    gpt = "gpt-4.1-mini"
    gemini = "gemini-2.0-flash"
    deepseek = "deepseek-chat"
}

Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-LocalIPv4Addresses {
    try {
        [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
            Where-Object { $_.OperationalStatus -eq "Up" -and $_.NetworkInterfaceType -ne "Loopback" } |
            ForEach-Object { $_.GetIPProperties().UnicastAddresses } |
            Where-Object { $_.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
            ForEach-Object { $_.Address.IPAddressToString } |
            Sort-Object -Unique
    } catch {
        @()
    }
}

function ConvertTo-ProtectedText {
    param([string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $protected = [System.Security.Cryptography.ProtectedData]::Protect(
        $bytes,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    [Convert]::ToBase64String($protected)
}

function ConvertFrom-ProtectedText {
    param([string]$Text)
    $bytes = [Convert]::FromBase64String($Text)
    $plain = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $bytes,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    [System.Text.Encoding]::UTF8.GetString($plain)
}

function Read-RequestJson {
    param($Request)
    $reader = [System.IO.StreamReader]::new($Request.InputStream, [System.Text.Encoding]::UTF8, $true)
    $raw = $reader.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @{}
    }
    try {
        $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Request JSON parse failed."
    }
}

function Write-Json {
    param($Response, [int]$StatusCode, $Body)
    $json = $Body | ConvertTo-Json -Depth 20
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = "application/json; charset=utf-8"
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.OutputStream.Close()
}

function Write-StaticFile {
    param($Response, [string]$FilePath)
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    $types = @{
        ".html" = "text/html; charset=utf-8"
        ".css" = "text/css; charset=utf-8"
        ".js" = "text/javascript; charset=utf-8"
        ".json" = "application/json; charset=utf-8"
        ".svg" = "image/svg+xml; charset=utf-8"
        ".png" = "image/png"
        ".jpg" = "image/jpeg"
        ".jpeg" = "image/jpeg"
        ".webp" = "image/webp"
        ".ico" = "image/x-icon"
        ".mp4" = "video/mp4"
    }
    $contentType = $types[$ext]
    if (-not $contentType) { $contentType = "application/octet-stream" }
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $Response.StatusCode = 200
    $Response.ContentType = $contentType
    $Response.Headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    $Response.Headers["Pragma"] = "no-cache"
    $Response.Headers["Expires"] = "0"
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Get-Settings {
    param([switch]$IncludeKey)
    if ((-not (Test-Path -LiteralPath $SettingsFile)) -and (Test-Path -LiteralPath $LegacySettingsFile)) {
        if (-not (Test-Path -LiteralPath $DataDir)) {
            New-Item -ItemType Directory -Path $DataDir | Out-Null
        }
        Copy-Item -LiteralPath $LegacySettingsFile -Destination $SettingsFile -Force
    }
    if (-not (Test-Path -LiteralPath $SettingsFile)) {
        return @{
            provider = "deepseek"
            model = $DefaultModels.deepseek
            hasApiKey = $false
        }
    }

    $saved = Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json
    $provider = if ($saved.provider) { [string]$saved.provider } else { "deepseek" }
    $model = if ($saved.model) { [string]$saved.model } else { $DefaultModels[$provider] }
    $result = @{
        provider = $provider
        model = $model
        hasApiKey = [bool]$saved.apiKey
    }
    if ($IncludeKey -and $saved.apiKey) {
        $result.apiKey = ConvertFrom-ProtectedText ([string]$saved.apiKey)
    }
    $result
}

function Clear-Settings {
    if (Test-Path -LiteralPath $SettingsFile) {
        Remove-Item -LiteralPath $SettingsFile -Force
    }
}

function Join-CodePoints {
    param([int[]]$Codes)
    -join ($Codes | ForEach-Object { [char]$_ })
}

function Get-Cn {
    param([string]$Key)
    switch ($Key) {
        "timeline" { Join-CodePoints @(0x65F6,0x95F4,0x8F74,0x5206,0x955C,0xFF08,0x0043,0x006F,0x006E,0x0074,0x0069,0x006E,0x0075,0x006F,0x0075,0x0073,0x0020,0x0053,0x0074,0x006F,0x0072,0x0079,0x0062,0x006F,0x0061,0x0072,0x0064,0xFF09,0xFF1A) }
        "audio" { Join-CodePoints @(0x58F0,0x97F3,0xFF08,0x0041,0x0075,0x0064,0x0069,0x006F,0xFF09,0xFF1A) }
        "bgm" { Join-CodePoints @(0x914D,0x4E50,0xFF08,0x0042,0x0047,0x004D,0xFF09,0xFF1A) }
        "limits" { Join-CodePoints @(0x751F,0x6210,0x9650,0x5236,0xFF0C,0x907F,0x514D,0xFF1A) }
        "requirements" { Join-CodePoints @(0x8981,0x6C42,0xFF1A) }
        "shotSize" { Join-CodePoints @(0x666F,0x522B,0xFF1A) }
        "camera" { Join-CodePoints @(0x955C,0x5934,0xFF1A) }
        "visual" { Join-CodePoints @(0x753B,0x9762,0x52A8,0x4F5C,0x4E0E,0x60C5,0x7EEA,0xFF1A) }
        default { "" }
    }
}

function Get-SeedanceAExample {
    @"
Reference example style for Mode A. Learn the structure, density, and level of detail. Do not copy the animal content unless the user's source is about an animal.
Important: This example is a 7-second source example because the source contains 3 seconds + 4 seconds. The timing is not fixed. For any user source, the final prompt duration must equal the user's explicit source duration. If the user gives no duration, one prompt must be no longer than 15 seconds.

Netflix animal documentary style, continuous multi-shot video, dark apartment, cinematic night lighting, ultra-low light environment, handheld camera, natural motion blur, realistic cat fur texture, shallow depth of field, 4K resolution, hyper-realistic, dynamic transitions.

Timeline storyboard (Continuous Storyboard):
[0-3s: ear alert close-up] Extreme close-up of the same brown tabby cat's ears turning toward a faint sound. Low-light apartment, realistic fur detail, shallow depth of field, documentary handheld stillness.
[3-7s: paw tension before sprint] Detail shot of the same brown tabby cat's paws and hind legs on the wooden floor. The body lowers, claws grip the floor, muscles tense, ready to sprint. Handheld documentary camera, natural motion blur, realistic indoor night lighting.

Audio:
0-3s: extremely low room tone and faint ear-twitch sound. 3-7s: subtle claw friction on wood, tense breathing, soft floor vibration.

BGM:
No music. Pure documentary ambient sound to emphasize natural realism and quiet tension.

Generation limits, avoid:
Cat changing breed or fur color across cuts, distorted paws, unrealistic motion blur, inconsistent visual style between shots.

Requirements:
4K ultra HD, total duration exactly 7 seconds for this example, storyboard timing must match source duration, smooth multi-shot transitions, stable low-light noise control, realistic fur and body mechanics.
"@
}

function Get-ProfessionalPromptRules {
    @"
Professional Mode hard storyboard rules:
- Before writing the final SEEDANCE 2.0 prompt, internally build a complete shot-by-shot storyboard table from the user's source. For Word novel/script documents, the internal storyboard must cover the whole document, not only the first 15 seconds.
- Each storyboard row must contain: global time range, duration, shot type, camera movement, core action, dialogue if any, character reaction, sound, and whether the row can be grouped with the next row.
- If the user text or uploaded Word novel/script contains the format "character name + colon", such as "摄政王：" or "王妃（OS/画外音）：", treat the following sentence as spoken dialogue. Do not mistake it for action description. Estimate this dialogue at 2.5 to 3 Chinese characters per second, excluding punctuation and parenthetical speaker notes, then add time for breaths, pauses, facial reaction, key action, camera movement, and listener reaction.
- If the speaker label contains OS, VO, 画外音, 旁白, or 内心独白, the following sentence is still real voice-over dialogue. It must be counted by Chinese character length and timed at 2.5 to 3 Chinese characters per second. Never treat OS / voice-over as a short sound effect, emotion label, or instant thought.
- Every dialogue line marked by "character name + colon" in the source must appear verbatim in the final professional prompt exactly once, either as spoken dialogue or OS / voice-over. Do not summarize, paraphrase, omit, shorten, merge, or move it only into vague sound design.
- In the Timeline storyboard section, every segment must explicitly include a dialogue field: write "对白/画外音：原文台词" when there is dialogue, and write "对白/画外音：无台词" when there is no dialogue. The Audio section may repeat sound details, but it cannot be the only place where dialogue appears.
- If dialogue appears without the clear "character name + colon" format, still estimate speech duration using natural spoken Mandarin pace before assigning shot time. Natural Mandarin dialogue should not be faster than 3 Chinese characters per second unless the user explicitly asks for faster speech. If the user explicitly asks for faster speech, use the matching faster pace, but never force a long line into an unrealistically short shot.
- A shot that contains dialogue must have enough duration for the line to be spoken naturally plus the key action and camera movement in that same shot. Do not create a 4-second shot that requires a character to read a long paragraph.
- If one complete dialogue line cannot fit naturally inside one short segment, split that dialogue beat into 2 connected shots at a natural semantic pause. The first shot carries the first phrase group and the second shot continues the remaining phrase group. Keep the speaker identity and dialogue continuity clear; do not cut inside a word or unfinished phrase.
- After estimating the complete storyboard duration, generate prompts by selecting continuous neighboring storyboard shots. Each final professional prompt must be a complete SEEDANCE 2.0 prompt and should be no longer than 15 seconds unless the user's explicit duration rule requires otherwise. If the source is short text but the dialogue-timed storyboard exceeds 15 seconds, output multiple complete professional prompts labeled Prompt 1, Prompt 2, Prompt 3, etc.
- Each single professional prompt is one SEEDANCE 2.0 video and must end at or before 15 seconds. Never output one prompt with a timeline such as 0-16 seconds, 0-20 seconds, or any internal segment ending after 15 seconds. Split into Prompt 1, Prompt 2, Prompt 3 instead.
- When splitting, each prompt's internal timeline must restart from 0 seconds. Global source ranges may be shown in the prompt title only; internal storyboard segment times must be 0-15 seconds.
- Every time segment may keep only one core action. Do not pack multiple important actions into one vague segment.
- If more than two actions happen inside 4 seconds, split them into shorter shots.
- Every segment must clearly name a shot type such as 中景, 手部特写, 纸面特写, 反应特写, or 双人压迫构图. Do not omit shot type.
- Do not use one three-person same-frame shot to cover an entire video. If three characters are present, break the scene into purposeful singles, inserts, reaction shots, and pressure compositions.
- For any writing / paper / confrontation / maid-exit scene in the source, the action chain is mandatory and must appear in order: 写字 -> 停笔 -> 推纸 -> 看纸 -> 神色变化 -> 逼近 -> 丫鬟退场关门. Each action must be placed in its own clearly timed beat or shot; do not merge the whole chain into one wide shot.
- For that action chain, use clear shot types across the sequence: 中景 for spatial setup, 手部特写 for writing and stopping the pen, 纸面特写 for the paper, 反应特写 for looking at the paper and the expression change, 双人压迫构图 for the approach and pressure beat, then a separate exit/door-closing beat for the maid.
- Before final output, self-check that every source dialogue line after "角色名：" appears in full in the final Timeline storyboard. If any source dialogue is missing, rewrite before answering.
"@
}

function Get-MasterPromptRules {
    @"
Master Mode hard dialogue and timing rules:
- Master Mode must be built on top of Professional Mode, not replace it. First preserve the complete professional storyboard skeleton: all key scenes, all key actions, all source dialogue, all shot types, all camera movement, and the full action chain required by Professional Mode. Then add Master Mode acting details.
- Before writing the final master prompt, internally build a complete dialogue storyboard table from the user's source. For Word novel/script documents, the internal storyboard must cover the whole document, not only the first 15 seconds.
- The final master output must cover the full user source. Do not select only the most emotional 1 to 3 shots when the source contains more story beats.
- Every master prompt segment must contain both scene/action information and acting/performance information. Do not output only facial details, eyes, tone, or subtext without the concrete scene, position, action, and camera event.
- Required scene/action coverage for every segment: location, visible characters, shot type, camera movement, composition, character position, one core action, source dialogue or no-dialogue marker, and visible reaction.
- If the user text or uploaded Word novel/script contains the format "character name + colon", such as "摄政王：" or "王妃（OS/画外音）：", treat the following sentence as spoken dialogue. Do not mistake it for action description, narration, or a short reaction beat.
- Dialogue marked by "character name + colon" must be timed at 2.5 to 3 Chinese characters per second, excluding punctuation and parenthetical speaker notes. This applies equally to OS, VO, voice-over, narration, and inner monologue lines. Then add time for breath, semantic pause, emotional turn, eye movement, facial micro-expression, body action, camera movement, and listener reaction.
- A master prompt segment that contains dialogue must be long enough for the line to be spoken naturally plus its performance beat. Never put a long sentence or paragraph into 4 seconds.
- If one complete dialogue / OS / voice-over line cannot fit naturally inside one short segment, split it into 2 connected adjacent master segments at a natural semantic pause. The first segment carries the first phrase group and the second segment continues the remaining phrase group. Keep the speaker identity, emotional continuity, listener reaction, and visual continuity clear; do not cut inside a word or unfinished phrase.
- If the complete scene requires more than 15 seconds after dialogue timing is calculated, split it into multiple independent master prompts. Each single master prompt is one SEEDANCE 2.0 video and must be no longer than 15 seconds. Never output one prompt with a 20-second, 25-second, or 40-second duration.
- When a dialogue line is long enough that grouping it with the previous 1-2 scene beats would make the prompt exceed 15 seconds, make that speaking beat its own independent prompt. The previous actions become the previous prompt; the long speaking beat becomes the next prompt; the following reaction/action beats continue in later prompts as needed.
- Do not delete, summarize, or silently skip dialogue in order to fit a 15-second prompt. Long dialogue must expand the total duration and create more prompts.
- Keep dialogue continuity: do not cut inside a phrase, a sentence, or an unfinished meaning. Put shot changes at natural semantic pauses.
- Every segment must include: 台词, 语气, 关键词发音, 眼神, 表情, 动作/微表演, 潜台词, 听者反应. If a segment has no spoken line, write "台词：无台词，纯反应".
- Master Mode must prioritize acting direction. Do not collapse several story events into one general 镜头设计 paragraph; important actions and reactions must be placed into timed segments.
- Before final output, self-check every segment: if a dialogue line needs more time than the segment allows at 2.5 to 3 Chinese characters per second, extend the segment, split it into 2 connected adjacent master segments, or split the scene into more prompts.
- Before final output, self-check that the complete professional storyboard skeleton is still present. If any key scene, action, character movement, door/prop action, or source dialogue is missing, rewrite before answering.
- Before final output, self-check every prompt title and internal segment time range. Each prompt's global duration and each prompt's internal duration must be 15 seconds or less.
"@
}

function Save-Settings {
    param($Body)
    $provider = [string]$Body.provider
    $model = [string]$Body.model
    $apiKey = ([string]$Body.apiKey).Trim()

    if (@("gpt", "gemini", "deepseek") -notcontains $provider) {
            throw "Please choose GPT, Gemini, or DeepSeek."
    }
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        throw "Please enter an API Key."
    }
    if ([string]::IsNullOrWhiteSpace($model)) {
        $model = $DefaultModels[$provider]
    }
    if (-not (Test-Path -LiteralPath $DataDir)) {
        New-Item -ItemType Directory -Path $DataDir | Out-Null
    }

    @{
        provider = $provider
        model = $model
        apiKey = ConvertTo-ProtectedText $apiKey
        updatedAt = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json | Set-Content -LiteralPath $SettingsFile -Encoding UTF8
}

function New-GenerationPrompt {
    param([string]$Mode, [string]$Text)
    $clean = $Text.Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) {
        throw "Please enter source text."
    }
    if ($clean.Length -gt 5000) {
        throw "Short text input is currently limited to 5000 characters."
    }

    if ($Mode -eq "A") {
        $durationPlan = Get-SourceDurationPlan $clean
        $dialogueTimingPlan = Get-DialogueTimingPlan $clean
        $timelineTemplate = Get-SourceTimelineTemplate $clean
        $timelineHeading = Get-Cn "timeline"
        $audioHeading = Get-Cn "audio"
        $bgmHeading = Get-Cn "bgm"
        $limitsHeading = Get-Cn "limits"
        $requirementsHeading = Get-Cn "requirements"
        $professionalRules = Get-ProfessionalPromptRules
        return @"
You are Zhimengshi Mode A: SEEDANCE 2.0 Professional Prompt mode.

Task: Based on the user's source text under 5000 characters, generate professional prompt content that can be copied directly into Jimeng SEEDANCE 2.0. If the dialogue-timed storyboard is longer than 15 seconds, generate multiple complete prompts instead of compressing or omitting dialogue.

Output language: Chinese, with necessary English video-generation terms.

Core workflow:
The app itself does not analyze the plot locally. You, the external AI model, must read the user's source text, the rules, the reference example, and the output format together, then generate the final prompt according to these requirements.

Required structure:
Do not output analysis notes. Do not output Markdown numbering such as "1." or "2.". Output the final prompt only.
Do not output bracket placeholders such as [Opening paragraph], [One opening paragraph], [short Chinese title], or any template instructions.
You must replace every template hint with real prompt content.
If multiple prompts are needed, label them as Prompt 1, Prompt 2, Prompt 3. Every Prompt must include the same complete professional sections listed below.

$professionalRules

$durationPlan

$dialogueTimingPlan

Use these exact section headings:
$timelineHeading
$audioHeading
$bgmHeading
$limitsHeading
$requirementsHeading

Reference prompt example:
$(Get-SeedanceAExample)

Start with one dense Chinese style paragraph. It must include these English terms where useful: continuous multi-shot video, cinematic lighting, 4K resolution, hyper-realistic, dynamic transitions, and aspect ratio if the source mentions it.

$timelineHeading
$timelineTemplate
Every timeline segment must include:
- shot type / camera movement
- one core action
- dialogue field: 对白/画外音：...
- visible reaction or performance beat

$audioHeading
Write concrete ambient sound, action sound, and dialogue or no-dialogue sound design.

$bgmHeading
Write whether music is used, and describe the music style. If no music is suitable, explicitly say no BGM and use documentary ambient sound.

$limitsHeading
Write concrete negative constraints: character consistency, species/color consistency, style consistency, no clipping, no distorted motion, no fake plastic fluid, no wrong setting.

$requirementsHeading
Write final quality requirements: 4K, coherent timing, smooth transition, realistic motion, stable lighting, accurate physics when relevant.

Important:
- If the user source explicitly contains shot durations such as "3 seconds" and "4 seconds", you must add them and use that exact total duration. Do not stretch the prompt to 12 or 15 seconds.
- If explicit source durations are detected, the storyboard segment count and time ranges must follow those durations exactly.
- If the source does not provide explicit shot durations, infer the total duration from the internal storyboard, including natural Mandarin dialogue duration, key action duration, camera movement duration, and reaction beats. Do not blindly default to 12 or 15 seconds.
- Do not omit any source dialogue to keep the result short. If dialogue timing exceeds 15 seconds, split into multiple complete prompts.
- The output must be directly copyable into Jimeng SEEDANCE 2.0.

User source text:
$clean
"@
    }

    $professionalRules = Get-ProfessionalPromptRules
    $masterRules = Get-MasterPromptRules
    @"
You are Zhimengshi Mode B: SEEDANCE 2.0 Master Prompt mode, specialized for dialogue scenes.

Task: Based on the user's source text, first internally build the complete Professional Mode storyboard skeleton, then add Master Mode dialogue performance analysis, then output master-level SEEDANCE 2.0 prompts that cover the full source text. If the full dialogue-timed scene exceeds 15 seconds, split it into multiple complete master prompts instead of selecting only a few shots.

Output language: Chinese, with necessary English video-generation terms.

Core workflow:
The app itself does not analyze the plot locally. You, the external AI model, must read the user's source text, the Professional Mode rules, the Master Mode dialogue-scene rules, and the output format requirements together. The final result must preserve the full professional storyboard content and add master-level acting direction.

Professional Mode rules that must be preserved:
$professionalRules

$masterRules

Must follow:
- Do not output analysis notes, raw storyboard tables, character-analysis tables, Markdown tables, code fences, or conversational prefaces.
- The final answer must start directly with "提示词1" or "提示词1（全局时间：...）".
- Cover the full source text, not only the first 15 seconds and not only 1 to 3 selected shots.
- If the complete storyboard exceeds 15 seconds, output multiple complete prompts labeled 提示词1, 提示词2, 提示词3, etc. Each prompt must cover continuous neighboring storyboard shots, and each prompt's internal timing must restart from 0秒.
- Each prompt must contain a 镜头设计 section plus timed segments. The timed segments must contain concrete scene/action content first, then master-level performance details.
- When dialogue appears, shot switches must preserve dialogue continuity. Never cut inside a word group or unfinished meaning.
- In multi-character dialogue, after one person finishes a dialogue line under 4 seconds, provide a listener reaction shot for another key character.
- Each segment must include shot size, camera movement, dialogue, tone, eyes, facial expression, action or micro-performance.
- Maintain dialogue space and eye-line consistency: specify head direction, gaze direction, where the counterpart is, and composition.
- Analyze subtext and turn psychology into tone, eyes, facial expression, and action.
- Required segment structure:
  第一段（0-x秒）：中文标题
  - 场景/构图：
  - 核心动作：
  - 台词：
  - 语气：
  - 关键词发音：
  - 眼神：
  - 表情：
  - 动作/微表演：
  - 潜台词：
  - 听者反应：

User source text:
$clean
"@
}

function Get-SourceDurationPlan {
    param([string]$Text)
    $durations = Get-ExplicitDurations $Text
    if ($durations.Count -eq 0) {
        return "No explicit source duration was detected. Use the default A-mode timing: one prompt no longer than 15 seconds."
    }

    $total = 0.0
    $ranges = @()
    for ($i = 0; $i -lt $durations.Count; $i++) {
        $start = $total
        $total += $durations[$i]
        $ranges += ("Segment {0}: {1}-{2} seconds" -f ($i + 1), (Format-Seconds $start), (Format-Seconds $total))
    }

    @"
Explicit source durations detected:
- Durations: $($durations -join " + ") seconds
- Total duration: $(Format-Seconds $total) seconds
- Required storyboard timing:
$($ranges -join "`n")
You must use these time ranges exactly. Do not extend, pad, or change the total duration. Do not add any storyboard segment after $(Format-Seconds $total) seconds.
"@
}

function Get-ExplicitDurations {
    param([string]$Text)
    $matches = [regex]::Matches($Text, "(?<!\d)(\d+(?:\.\d+)?)\s*(?:s|sec|second|seconds|\u79D2)")
    if ($matches.Count -eq 0) {
        return @()
    }

    $durations = @()
    foreach ($m in $matches) {
        $value = [double]$m.Groups[1].Value
        if ($value -gt 0 -and $value -le 60) { $durations += $value }
    }
    return $durations
}

function Get-SourceTimelineTemplate {
    param([string]$Text)
    $shotSize = Get-Cn "shotSize"
    $camera = Get-Cn "camera"
    $visual = Get-Cn "visual"
    $durations = Get-ExplicitDurations $Text
    if ($durations.Count -eq 0) {
        return @"
Use a coherent Chinese storyboard no longer than 15 seconds. Choose the number of segments according to the content. Do not default to 15 seconds unless the source needs it.
"@
    }

    $total = 0.0
    $lines = @()
    for ($i = 0; $i -lt $durations.Count; $i++) {
        $start = $total
        $total += $durations[$i]
        $lines += ("[{0}-{1}s: Chinese title] {2} concrete shot size. {3} concrete camera movement. {4} concrete visual action and emotion." -f (Format-Seconds $start), (Format-Seconds $total), $shotSize, $camera, $visual)
    }
    $lines -join "`n"
}

function Get-ExplicitTotalSeconds {
    param([string]$Text)
    $durations = Get-ExplicitDurations $Text
    if ($durations.Count -eq 0) { return $null }
    $total = 0.0
    foreach ($d in $durations) { $total += $d }
    return $total
}

function Get-MaxTimelineEndSecond {
    param([string]$Text)
    $max = 0.0
    $rangeSep = "(?:-|$([char]0x2014)|$([char]0x2013)|~|$([char]0x81F3)|$([char]0x5230))"
    $secondUnit = "(?:s|sec|second|seconds|$([char]0x79D2))"
    $pattern = "(\d+(?:\.\d+)?)\s*$rangeSep\s*(\d+(?:\.\d+)?)\s*$secondUnit"
    try {
        $matches = [regex]::Matches($Text, $pattern)
    } catch {
        return 0.0
    }
    foreach ($m in $matches) {
        $end = [double]$m.Groups[2].Value
        if ($end -gt $max) { $max = $end }
    }
    return $max
}

function New-DurationCorrectionPrompt {
    param([string]$OriginalPrompt, [string]$BadOutput, [double]$TotalSeconds)
    $professionalRules = Get-ProfessionalPromptRules
    @"
The previous output violated a hard timing rule.

Hard rule:
The user provided explicit source durations. The total video duration must be exactly $(Format-Seconds $TotalSeconds) seconds. The storyboard must end at $(Format-Seconds $TotalSeconds) seconds. Do not add any segment after that time. Do not stretch to 12 seconds or 15 seconds.

Professional rules that must still be preserved during the rewrite:
$professionalRules

Rewrite the output only. Keep the same style and content quality, but fix the timing so the final prompt duration exactly matches $(Format-Seconds $TotalSeconds) seconds.

Original task:
$OriginalPrompt

Incorrect previous output:
$BadOutput
"@
}

function Get-SourceDialogueLines {
    param([string]$Text)
    $lines = @()
    foreach ($rawLine in (([string]$Text) -split "\r?\n")) {
        $line = ([string]$rawLine).Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $colonIndex = $line.IndexOf(":")
        $fullColonIndex = $line.IndexOf([char]0xFF1A)
        if ($colonIndex -lt 0 -or ($fullColonIndex -ge 0 -and $fullColonIndex -lt $colonIndex)) {
            $colonIndex = $fullColonIndex
        }
        if ($colonIndex -le 0 -or $colonIndex -ge ($line.Length - 1) -or $colonIndex -gt 30) { continue }
        $speaker = $line.Substring(0, $colonIndex).Trim()
        $dialogue = $line.Substring($colonIndex + 1).Trim()
        if ([string]::IsNullOrWhiteSpace($dialogue)) { continue }
        $badSpeakerMarks = @(",", ".", "!", "?", ";", [string][char]0xFF0C, [string][char]0x3002, [string][char]0xFF01, [string][char]0xFF1F, [string][char]0xFF1B, [string][char]0x3001)
        $badSpeaker = $false
        foreach ($mark in $badSpeakerMarks) {
            if ($speaker.Contains($mark)) { $badSpeaker = $true; break }
        }
        if ($badSpeaker) { continue }
        while ($dialogue.StartsWith("(") -or $dialogue.StartsWith([string][char]0xFF08)) {
            $close = if ($dialogue.StartsWith("(")) { $dialogue.IndexOf(")") } else { $dialogue.IndexOf([char]0xFF09) }
            if ($close -lt 0) { break }
            $dialogue = $dialogue.Substring($close + 1).Trim()
        }
        if (-not [string]::IsNullOrWhiteSpace($dialogue)) { $lines += $dialogue }
    }
    return $lines
}

function Get-ChineseCharacterCount {
    param([string]$Text)
    return ([regex]::Matches(([string]$Text), "[\u4e00-\u9fff]")).Count
}

function Get-SourceDialogueTimingSummary {
    param([string]$Text)
    $dialogues = @(Get-SourceDialogueLines $Text)
    if ($dialogues.Count -eq 0) {
        return [pscustomobject]@{
            totalMinimumSeconds = 0.0
            lines = @()
        }
    }

    $total = 0.0
    $items = @()
    for ($i = 0; $i -lt $dialogues.Count; $i++) {
        $dialogue = [string]$dialogues[$i]
        $count = Get-ChineseCharacterCount $dialogue
        $minimum = if ($count -gt 0) { [Math]::Ceiling(($count / 3.0) * 10) / 10 } else { 0.0 }
        $total += $minimum
        $items += [pscustomobject]@{
            index = $i + 1
            text = $dialogue
            chineseChars = $count
            minimumSeconds = $minimum
        }
    }

    [pscustomobject]@{
        totalMinimumSeconds = [Math]::Ceiling($total * 10) / 10
        lines = $items
    }
}

function Get-DialogueTimingPlan {
    param([string]$Text)
    $summary = Get-SourceDialogueTimingSummary $Text
    if ($summary.lines.Count -eq 0) {
        return "No source dialogue or voice-over line marked by character-name colon was detected."
    }

    $rows = @()
    foreach ($item in $summary.lines) {
        $rows += ("Dialogue {0}: {1} Chinese characters, minimum speaking time {2} seconds at 2.5 to 3 chars/second. Text: {3}" -f $item.index, $item.chineseChars, (Format-Seconds $item.minimumSeconds), $item.text)
    }

    @"
Source dialogue / voice-over timing plan:
$($rows -join "`n")
Minimum total speaking time for all dialogue and OS / voice-over only: $(Format-Seconds $summary.totalMinimumSeconds) seconds.
This is only the speech floor. The final storyboard duration must be longer after adding action, camera movement, pauses, reactions, door/prop actions, and transitions. Do not compress these dialogue or voice-over lines into shorter segments.
"@
}

function Get-SourceDialogueMinimumSeconds {
    param([string]$Text)
    return [double](Get-SourceDialogueTimingSummary $Text).totalMinimumSeconds
}

function Test-ProfessionalOutputMissingDialogue {
    param([string]$SourceText, [string]$OutputText)
    $dialogues = @(Get-SourceDialogueLines $SourceText)
    if ($dialogues.Count -eq 0) { return $false }
    $normalizedOutput = [regex]::Replace(([string]$OutputText), "\s+", "")
    foreach ($dialogue in $dialogues) {
        $normalizedDialogue = [regex]::Replace($dialogue, "\s+", "")
        if ($normalizedDialogue.Length -gt 0 -and -not $normalizedOutput.Contains($normalizedDialogue)) {
            return $true
        }
    }
    return $false
}

function New-ProfessionalDialogueCorrectionPrompt {
    param([string]$OriginalPrompt, [string]$BadOutput, [string]$SourceText)
    $professionalRules = Get-ProfessionalPromptRules
    $dialogues = @(Get-SourceDialogueLines $SourceText)
    @"
The previous professional prompt omitted source dialogue, which is forbidden.

Hard rule:
Every source dialogue line after "character name + colon" must appear verbatim in the final Timeline storyboard, using "对白/画外音：". Do not summarize, paraphrase, shorten, or move dialogue only into Audio.

Required source dialogue lines:
$($dialogues -join "`n")

Professional rules:
$professionalRules

Rewrite the output completely. If the dialogue-timed storyboard exceeds 15 seconds, split it into multiple complete professional prompts labeled Prompt 1, Prompt 2, Prompt 3, etc. Each prompt must include Timeline storyboard, Audio, BGM, generation limits, and requirements.

Original task:
$OriginalPrompt

Incorrect previous output:
$BadOutput
"@
}

function Test-ProfessionalOutputTooShortForDialogue {
    param([string]$SourceText, [string]$OutputText)
    $minimum = Get-SourceDialogueMinimumSeconds $SourceText
    if ($minimum -le 0) { return $false }
    if (([string]$OutputText) -match "Prompt\s*2|提示词\s*2|提示词2") { return $false }
    $maxEnd = Get-MaxTimelineEndSecond $OutputText
    if ($maxEnd -le 0) { return $false }
    return ($maxEnd + 0.05) -lt $minimum
}

function Test-ProfessionalSegmentTooShortForDialogue {
    param([string]$SourceText, [string]$OutputText)
    $dialogues = @(Get-SourceDialogueLines $SourceText)
    if ($dialogues.Count -eq 0) { return $false }

    $text = [string]$OutputText
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }

    $rangeSep = "(?:-|$([char]0x2014)|$([char]0x2013)|~|$([char]0x81F3)|$([char]0x5230))"
    $secondUnit = "(?:s|sec|second|seconds|$([char]0x79D2))"
    $pattern = "(\d+(?:\.\d+)?)\s*$rangeSep\s*(\d+(?:\.\d+)?)\s*$secondUnit"
    $matches = [regex]::Matches($text, $pattern)
    if ($matches.Count -eq 0) { return $false }

    $normalizedDialogues = @()
    foreach ($dialogue in $dialogues) {
        $normalizedDialogue = [regex]::Replace(([string]$dialogue), '[^\u4e00-\u9fff]', '')
        if ($normalizedDialogue.Length -gt 0) {
            $chineseCount = Get-ChineseCharacterCount $dialogue
            $normalizedDialogues += [pscustomobject]@{
                text = [string]$dialogue
                normalized = $normalizedDialogue
                minimumSeconds = if ($chineseCount -gt 0) { [Math]::Ceiling(($chineseCount / 3.0) * 10) / 10 } else { 0.0 }
            }
        }
    }

    for ($i = 0; $i -lt $matches.Count; $i++) {
        $m = $matches[$i]
        $start = [double]$m.Groups[1].Value
        $end = [double]$m.Groups[2].Value
        if ($end -le $start) { continue }

        $blockStart = $m.Index
        $blockEnd = if ($i + 1 -lt $matches.Count) { $matches[$i + 1].Index } else { $text.Length }
        if ($blockEnd -le $blockStart) { continue }

        $block = $text.Substring($blockStart, $blockEnd - $blockStart)
        $normalizedBlock = [regex]::Replace($block, '[^\u4e00-\u9fff]', '')
        $duration = $end - $start

        foreach ($item in $normalizedDialogues) {
            if ($item.minimumSeconds -gt 0 -and $normalizedBlock.Contains($item.normalized) -and (($duration + 0.05) -lt $item.minimumSeconds)) {
                return $true
            }
        }
    }

    return $false
}

function New-ProfessionalDialogueTimingCorrectionPrompt {
    param([string]$OriginalPrompt, [string]$BadOutput, [string]$SourceText)
    $professionalRules = Get-ProfessionalPromptRules
    $dialogueTimingPlan = Get-DialogueTimingPlan $SourceText
    @"
The previous professional prompt violated dialogue / voice-over timing.

Hard rule:
All dialogue and OS / voice-over lines marked by "character name + colon" must be timed at 2.5 to 3 Chinese characters per second, excluding punctuation and parenthetical tone notes. This applies equally to spoken dialogue and OS / voice-over. The final storyboard duration must be longer than the minimum speaking time after adding action, camera movement, pauses, reactions, door/prop actions, and transitions.

If one complete dialogue or voice-over line is too long for one segment, split it into 2 connected adjacent shots at natural semantic pauses. Do not compress a long line into a 2-4 second segment. The first shot carries the first phrase group; the second shot continues the remaining phrase group, while preserving speaker identity and visual continuity.

$dialogueTimingPlan

Professional rules:
$professionalRules

Rewrite the output completely. If the dialogue-timed storyboard exceeds 15 seconds, split it into multiple complete professional prompts labeled Prompt 1, Prompt 2, Prompt 3, etc. Do not compress long dialogue or voice-over into 2-4 second segments.

Original task:
$OriginalPrompt

Incorrect previous output:
$BadOutput
"@
}

function New-ProfessionalSegmentTimingCorrectionPrompt {
    param([string]$OriginalPrompt, [string]$BadOutput, [string]$SourceText)
    $professionalRules = Get-ProfessionalPromptRules
    $dialogueTimingPlan = Get-DialogueTimingPlan $SourceText
    @"
The previous professional prompt placed too much dialogue / voice-over inside a short timed segment.

Hard rule:
Every single Timeline segment that contains dialogue or OS / voice-over must allow the spoken text to finish at 2.5 to 3 Chinese characters per second, excluding punctuation and parenthetical tone notes. Then add time for the visible core action, camera movement, breath, pause, expression change, and listener reaction.

Segment splitting rule:
- If a complete dialogue line cannot fit naturally inside one short segment, split that dialogue beat into 2 connected adjacent shots.
- Split only at a natural semantic pause, never inside a word or unfinished phrase.
- Keep the same speaker and dialogue continuity clear in both shots.
- Do not put a long sentence or paragraph into 2, 3, or 4 seconds.
- Each final SEEDANCE 2.0 prompt must still end at or before 15 seconds. If the corrected timing exceeds 15 seconds, split into Prompt 1, Prompt 2, Prompt 3, etc.

$dialogueTimingPlan

Professional rules:
$professionalRules

Rewrite the output completely.

Original task:
$OriginalPrompt

Incorrect previous output:
$BadOutput
"@
}

function Test-ProfessionalPromptOver15Seconds {
    param([string]$OutputText)
    $text = [string]$OutputText
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }

    $hasMultiplePrompts = $text -match "Prompt\s*2|Prompt\s+#?2|提示词\s*2|提示词2"
    $maxEnd = Get-MaxTimelineEndSecond $text
    if (-not $hasMultiplePrompts -and $maxEnd -gt 15.05) { return $true }

    $rangeSep = "(?:-|$([char]0x2014)|$([char]0x2013)|~|$([char]0x81F3)|$([char]0x5230))"
    $secondUnit = "(?:s|sec|second|seconds|$([char]0x79D2))"
    $pattern = "(\d+(?:\.\d+)?)\s*$rangeSep\s*(\d+(?:\.\d+)?)\s*$secondUnit"
    $matches = [regex]::Matches($text, $pattern)
    foreach ($m in $matches) {
        $start = [double]$m.Groups[1].Value
        $end = [double]$m.Groups[2].Value
        if (($end - $start) -gt 15.05) { return $true }
    }

    return $false
}

function New-ProfessionalOver15CorrectionPrompt {
    param([string]$OriginalPrompt, [string]$BadOutput, [string]$SourceText)
    $professionalRules = Get-ProfessionalPromptRules
    $dialogueTimingPlan = Get-DialogueTimingPlan $SourceText
    @"
The previous professional prompt violated the SEEDANCE 2.0 duration limit.

Hard rule:
Each single SEEDANCE 2.0 video prompt must be no longer than 15 seconds. Do not output one Timeline storyboard that ends after 15 seconds, such as 13.5-16 seconds. If the full source scene needs more than 15 seconds, split it into multiple complete professional prompts labeled Prompt 1, Prompt 2, Prompt 3, etc.

Splitting rule:
- Keep each prompt's internal timeline starting at 0 seconds.
- Each prompt's internal timeline must end at or before 15 seconds.
- Preserve all source dialogue, OS / voice-over, actions, camera movement, and reactions.
- If a long dialogue or voice-over beat would make the current prompt exceed 15 seconds, move that beat into the next prompt or make it its own prompt.

$dialogueTimingPlan

Professional rules:
$professionalRules

Rewrite the output completely.

Original task:
$OriginalPrompt

Incorrect previous output:
$BadOutput
"@
}

function New-MasterCoverageCorrectionPrompt {
    param([string]$OriginalPrompt, [string]$BadOutput, [string]$SourceText)
    $professionalRules = Get-ProfessionalPromptRules
    $masterRules = Get-MasterPromptRules
    $dialogues = @(Get-SourceDialogueLines $SourceText)
    @"
The previous master prompt missed required source coverage.

Hard problem to fix:
- The master prompt must be built on the Professional Mode storyboard skeleton.
- It must preserve all key scenes, all key actions, all source dialogue, all character positions, all prop/door actions, and then add master-level acting details.
- It must not output only close-up details, facial details, eyes, tone, or subtext while losing important story content.
- Every source dialogue line after "character name + colon" must appear verbatim in the final timed segments.

Required source dialogue lines:
$($dialogues -join "`n")

Professional Mode rules to preserve:
$professionalRules

Master Mode rules to add:
$masterRules

Rewrite the output completely. If the dialogue-timed scene exceeds 15 seconds, split it into multiple complete master prompts labeled 提示词1, 提示词2, 提示词3, etc. Each segment must include 场景/构图, 核心动作, 台词, 语气, 关键词发音, 眼神, 表情, 动作/微表演, 潜台词, 听者反应.
Each single prompt must be no longer than 15 seconds. If a long character speaking beat plus the previous 1-2 scene beats would exceed 15 seconds, make that speaking beat its own independent prompt. Never output a prompt title like 全局时间：20-40秒.

Original task:
$OriginalPrompt

Incorrect previous output:
$BadOutput
"@
}

function New-MasterFormatCorrectionPrompt {
    param([string]$OriginalPrompt, [string]$BadOutput)
    $professionalRules = Get-ProfessionalPromptRules
    $masterRules = Get-MasterPromptRules
    @"
The previous output violated the Master Mode final-output format.

Rewrite the output completely.

Hard forbidden content:
- Do not output storyboard table.
- Do not output character analysis table.
- Do not output "main speaking character analysis".
- Do not output Markdown tables.
- Do not output any analysis section before the prompts.
- Do not output English labels such as Shot design, Segment, Dialogue, Tone, Eyes, Facial expression, Subtext, Listener reaction.
- Do not use global time ranges inside prompt segments. Each prompt is an independent Seedance video and its internal segment timing must start from 0 seconds.
- Do not output any single prompt whose global duration exceeds 15 seconds. A title like "提示词2（全局时间：20-40秒）" is forbidden because it is 20 seconds long.

$masterRules

Professional Mode rules that must be preserved:
$professionalRules

Final output must start directly with:
提示词1（全局时间：start-end秒；本条提示词内部时间从0秒开始）

Each prompt must use this exact Chinese structure:
提示词N（全局时间：start-end秒，供用户识别原剧本位置；本条提示词内部时间从0秒开始）
镜头设计：
- 景别：
- 镜头运动：
- 构图：
- 人物朝向与视线：

第一段（0-x秒）：中文小标题
- 场景/构图：
- 核心动作：
- 台词：
- 语气：
- 关键词发音：
- 眼神：
- 表情：
- 动作/微表演：
- 潜台词：
- 听者反应：

第二段（x-y秒）：中文小标题
- 场景/构图：
- 核心动作：
- 台词：
- 语气：
- 关键词发音：
- 眼神：
- 表情：
- 动作/微表演：
- 潜台词：
- 听者反应：

第三段（y-z秒）：中文小标题
- 场景/构图：
- 核心动作：
- 台词：
- 语气：
- 关键词发音：
- 眼神：
- 表情：
- 动作/微表演：
- 潜台词：
- 听者反应：

Rules:
- Output pure Chinese. All labels and content must be Chinese. Only the fixed model name SEEDANCE 2.0 may remain English.
- Do not output English words such as Prompt, Master Prompt, SCENE START, Shot, Close-up, Medium Shot, Insert Shot, Subject, Tone, Eyes, Dialogue, Subtext, Listener reaction.
- If there is no dialogue in a segment, write "台词：无台词，纯反应" and still provide tone, eyes, expression, action, subtext, listener reaction.
- If a character speaks, include keyword delivery for important words.
- After a speaking line, include the listener's reaction.
- Preserve the full story coverage, but rebuild timing if the previous output compressed dialogue unrealistically. Dialogue marked by "character name + colon" must follow 2.5 to 3 Chinese characters per second plus performance time.
- Preserve every key scene and action from the Professional Mode skeleton. Do not output only close-up details or performance notes.
- If a long character speaking beat plus the previous 1-2 scene beats would exceed 15 seconds, put that character speaking beat into its own prompt. Then continue later actions in the next prompt.
- Every prompt title's global range must be 15 seconds or less. Allowed examples: global 0-12 seconds, 12-24 seconds, 24-36 seconds. Forbidden example: global 20-40 seconds.
- Each prompt title may keep the global source range, but all internal segment time ranges must start at 0 seconds in that prompt.

Original task:
$OriginalPrompt

Incorrect previous output:
$BadOutput
"@
}

function New-MasterDialogueTimingCorrectionPrompt {
    param([string]$OriginalPrompt, [string]$BadOutput, [string]$SourceText)
    $professionalRules = Get-ProfessionalPromptRules
    $masterRules = Get-MasterPromptRules
    $dialogueTimingPlan = Get-DialogueTimingPlan $SourceText
    @"
The previous master prompt violated dialogue / OS / voice-over timing.

Hard rule:
All dialogue, OS, VO, voice-over, narration, and inner monologue lines marked by "character name + colon" must be timed at 2.5 to 3 Chinese characters per second, excluding punctuation and parenthetical tone notes. Then add time for breath, semantic pause, keyword delivery, eye movement, facial micro-expression, body action, camera movement, and listener reaction.

Master segment splitting rule:
- If one complete dialogue / OS / voice-over line cannot fit naturally inside one short segment, split it into 2 connected adjacent master segments at a natural semantic pause.
- The first segment carries the first phrase group; the second segment continues the remaining phrase group.
- Keep the same speaker identity, emotional continuity, visual continuity, and listener reaction clear.
- Do not put a long sentence or paragraph into 2, 3, or 4 seconds.
- Each single SEEDANCE 2.0 master prompt must still end at or before 15 seconds. If corrected timing exceeds 15 seconds, split into multiple complete master prompts.

$dialogueTimingPlan

Master Mode rules:
$masterRules

Professional Mode skeleton rules to preserve:
$professionalRules

Rewrite the output completely. Preserve the full Professional Mode storyboard skeleton and add Master Mode acting details. Do not output only close-up details or analysis notes.

Original task:
$OriginalPrompt

Incorrect previous output:
$BadOutput
"@
}

function Test-MasterOutputNeedsRewrite {
    param([string]$Text)
    if ($Text -match "\|[-\s]*\|") { return $true }
    if ($Text -match "storyboard table|character analysis|main speaking character analysis|SCENE START|Master Prompt|Prompt\s*\(|Shot\s*\d|Index\s*\d") { return $true }
    if ($Text -match "Shot design|Segment\s+\d|Dialogue:|Tone:|Keyword delivery:|Eyes:|Facial expression:|Subtext:|Listener reaction:|Close-up|INSERT SHOT|SUBTEXT|EYE-LINE") { return $true }
    $story = Join-CodePoints @(0x6545,0x4E8B,0x677F,0x8868,0x683C)
    $chars = Join-CodePoints @(0x4E3B,0x8981,0x8BF4,0x8BDD,0x89D2,0x8272,0x5206,0x6790)
    if ($Text.Contains($story) -or $Text.Contains($chars)) { return $true }
    $shotDesignCn = Join-CodePoints @(0x955C,0x5934,0x8BBE,0x8BA1)
    $firstSegmentCn = Join-CodePoints @(0x7B2C,0x4E00,0x6BB5)
    $secondSegmentCn = Join-CodePoints @(0x7B2C,0x4E8C,0x6BB5)
    if (-not $Text.Contains($shotDesignCn) -or -not $Text.Contains($firstSegmentCn) -or -not $Text.Contains($secondSegmentCn)) { return $true }
    $sceneCompositionCn = (Join-CodePoints @(0x573A,0x666F)) + "/" + (Join-CodePoints @(0x6784,0x56FE))
    $coreActionCn = Join-CodePoints @(0x6838,0x5FC3,0x52A8,0x4F5C)
    if (-not $Text.Contains($sceneCompositionCn) -or -not $Text.Contains($coreActionCn)) { return $true }
    if (Test-MasterPromptOver15Seconds $Text) { return $true }
    $englishLetters = ([regex]::Matches($Text, "[A-Za-z]")).Count
    $chineseChars = ([regex]::Matches($Text, "[\u4e00-\u9fff]")).Count
    if ($englishLetters -gt 120 -and $englishLetters -gt ($chineseChars * 0.18)) { return $true }
    return $false
}

function Test-MasterPromptOver15Seconds {
    param([string]$Text)
    foreach ($rawLine in (([string]$Text) -split "\r?\n")) {
        $line = ([string]$rawLine).Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $rangeText = $line
        $globalTimeCn = -join ([char]0x5168, [char]0x5C40, [char]0x65F6, [char]0x95F4)
        $firstCn = [string][char]0x7B2C
        $segmentCn = [string][char]0x6BB5
        if ($line.Contains($globalTimeCn)) {
            $idx = $line.IndexOf($globalTimeCn)
            $rangeText = $line.Substring($idx)
        } elseif (-not ($line.StartsWith($firstCn) -and $line.Contains($segmentCn))) {
            continue
        }

        $nums = [regex]::Matches($rangeText, "\d+(?:\.\d+)?")
        if ($nums.Count -lt 2) { continue }
        $start = [double]$nums[0].Value
        $end = [double]$nums[1].Value
        if (($end - $start) -gt 15.05) { return $true }
    }
    return $false
}

function Clear-MasterOutputExtraText {
    param([string]$Text)
    $clean = ([string]$Text).Trim()
    $promptCn = Join-CodePoints @(0x63D0,0x793A,0x8BCD)
    $shotDesignCn = Join-CodePoints @(0x955C,0x5934,0x8BBE,0x8BA1)
    $idx = $clean.IndexOf($promptCn)
    if ($idx -lt 0) { $idx = $clean.IndexOf($shotDesignCn) }
    if ($idx -gt 0) {
        $clean = $clean.Substring($idx).Trim()
    }
    $clean = [regex]::Replace($clean, '(?m)^\s*(好的|收到|我已收到|基于.*?规则.*?|下面.*?生成.*?|以下.*?提示.*?|---)\s*$', "")
    $clean = $clean.Replace('```', "")
    $clean = [regex]::Replace($clean, '(?m)^\s*#{1,6}\s*', "")
    $clean = $clean.Replace('**', "")
    $clean.Trim()
}

function Repair-MasterOutput {
    param($Settings, [string]$Prompt, [string]$Content)
    $fixed = Clear-MasterOutputExtraText $Content
    for ($attempt = 0; $attempt -lt 2 -and (Test-MasterOutputNeedsRewrite $fixed); $attempt++) {
        $fixed = Invoke-AI $Settings (New-MasterFormatCorrectionPrompt -OriginalPrompt $Prompt -BadOutput $fixed)
        $fixed = Clear-MasterOutputExtraText $fixed
    }
    return $fixed
}

function Format-Seconds {
    param([double]$Value)
    if ([Math]::Abs($Value - [Math]::Round($Value)) -lt 0.001) {
        return ([int][Math]::Round($Value)).ToString()
    }
    return ([Math]::Round($Value, 1)).ToString("0.0", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-TestSuccessMessage {
    -join @(
        [char]0x7EC7,
        [char]0x68A6,
        [char]0x5E08,
        [char]0x6A21,
        [char]0x578B,
        [char]0x8FDE,
        [char]0x63A5,
        [char]0x6210,
        [char]0x529F,
        [char]0x3002
    )
}

function Invoke-OpenAICompatible {
    param([string]$Url, [string]$ApiKey, [string]$Model, [string]$Prompt)
    $body = @{
        model = $Model
        messages = @(
            @{
                role = "system"
                content = "You are an expert in film storyboards, short-drama prompts, and Seedance 2.0 prompts. Output only the requested content."
            },
            @{
                role = "user"
                content = $Prompt
            }
        )
        temperature = 0.7
    } | ConvertTo-Json -Depth 20

    $response = Invoke-JsonPostUtf8 -Url $Url -Headers @{
        Authorization = "Bearer $ApiKey"
        "Content-Type" = "application/json; charset=utf-8"
    } -Body $body

    $response.choices[0].message.content
}

function Invoke-Gemini {
    param([string]$ApiKey, [string]$Model, [string]$Prompt)
    $encodedModel = [uri]::EscapeDataString($Model)
    $encodedKey = [uri]::EscapeDataString($ApiKey)
    $url = "https://generativelanguage.googleapis.com/v1beta/models/$encodedModel`:generateContent?key=$encodedKey"
    $body = @{
        contents = @(
            @{
                parts = @(
                    @{ text = $Prompt }
                )
            }
        )
        generationConfig = @{
            temperature = 0.7
        }
    } | ConvertTo-Json -Depth 20

    $response = Invoke-JsonPostUtf8 -Url $url -Headers @{
        "Content-Type" = "application/json; charset=utf-8"
    } -Body $body
    ($response.candidates[0].content.parts | ForEach-Object { $_.text }) -join ""
}

function Invoke-JsonPostUtf8 {
    param([string]$Url, $Headers, [string]$Body)
    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.Method = "POST"
    $request.ContentType = "application/json; charset=utf-8"
    $request.Accept = "application/json"

    foreach ($key in $Headers.Keys) {
        if ($key -ieq "Content-Type") { continue }
        if ($key -ieq "Accept") { continue }
        $request.Headers[$key] = [string]$Headers[$key]
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $request.ContentLength = $bytes.Length
    $stream = $request.GetRequestStream()
    try {
        $stream.Write($bytes, 0, $bytes.Length)
    } finally {
        $stream.Dispose()
    }

    try {
        $response = $request.GetResponse()
        $responseStream = $response.GetResponseStream()
        try {
            $reader = [System.IO.StreamReader]::new($responseStream, [System.Text.Encoding]::UTF8)
            try {
                return ($reader.ReadToEnd() | ConvertFrom-Json)
            } finally {
                $reader.Dispose()
            }
        } finally {
            $response.Dispose()
        }
    } catch [System.Net.WebException] {
        $errResponse = $_.Exception.Response
        if ($errResponse) {
            $errStream = $errResponse.GetResponseStream()
            $reader = [System.IO.StreamReader]::new($errStream, [System.Text.Encoding]::UTF8)
            $errText = $reader.ReadToEnd()
            $reader.Dispose()
            try {
                $errJson = $errText | ConvertFrom-Json
                if ($errJson.error.message) { throw $errJson.error.message }
            } catch {
                throw $errText
            }
        }
        throw $_.Exception.Message
    }
}

function Invoke-AI {
    param($Settings, [string]$Prompt)
    switch ($Settings.provider) {
        "gpt" {
            Invoke-OpenAICompatible -Url "https://api.openai.com/v1/chat/completions" -ApiKey $Settings.apiKey -Model $Settings.model -Prompt $Prompt
        }
        "deepseek" {
            Invoke-OpenAICompatible -Url "https://api.deepseek.com/v1/chat/completions" -ApiKey $Settings.apiKey -Model $Settings.model -Prompt $Prompt
        }
        "gemini" {
            Invoke-Gemini -ApiKey $Settings.apiKey -Model $Settings.model -Prompt $Prompt
        }
        default {
            throw "Unknown model provider."
        }
    }
}

function ConvertFrom-XmlText {
    param([string]$Text)
    [System.Net.WebUtility]::HtmlDecode($Text)
}

function ConvertTo-XmlText {
    param([string]$Text)
    [System.Security.SecurityElement]::Escape($Text)
}

function Get-ZipText {
    param($Archive, [string]$EntryName)
    $entry = $Archive.GetEntry($EntryName)
    if (-not $entry) { return $null }
    $stream = $entry.Open()
    try {
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally {
        $stream.Dispose()
    }
}

function Read-XlsxRows {
    param([byte[]]$Bytes)
    $temp = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllBytes($temp, $Bytes)
    $archive = $null
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($temp)
        $shared = @()
        $sharedXml = Get-ZipText $archive "xl/sharedStrings.xml"
        if ($sharedXml) {
            [regex]::Matches($sharedXml, "<si[\s\S]*?</si>") | ForEach-Object {
                $parts = [regex]::Matches($_.Value, "<t[^>]*>([\s\S]*?)</t>") | ForEach-Object {
                    ConvertFrom-XmlText $_.Groups[1].Value
                }
                $shared += ($parts -join "")
            }
        }

        $sheetEntry = $archive.Entries | Where-Object { $_.FullName -like "xl/worksheets/sheet*.xml" } | Select-Object -First 1
        if (-not $sheetEntry) { throw "No worksheet found in Excel file." }
        $sheetXml = Get-ZipText $archive $sheetEntry.FullName
        [xml]$xml = $sheetXml
        $rows = @()

        foreach ($rowNode in $xml.GetElementsByTagName("row")) {
            $rowMap = @{}
            foreach ($cell in $rowNode.GetElementsByTagName("c")) {
                $ref = $cell.GetAttribute("r")
                if (-not $ref) { continue }
                $col = ([regex]::Match($ref, "^[A-Z]+")).Value
                $type = $cell.GetAttribute("t")
                $valueNode = $cell.GetElementsByTagName("v") | Select-Object -First 1
                $inlineNode = $cell.GetElementsByTagName("t") | Select-Object -First 1
                $value = ""
                if ($type -eq "s" -and $valueNode) {
                    $idx = [int]$valueNode.InnerText
                    if ($idx -ge 0 -and $idx -lt $shared.Count) { $value = $shared[$idx] }
                } elseif ($inlineNode) {
                    $value = $inlineNode.InnerText
                } elseif ($valueNode) {
                    $value = $valueNode.InnerText
                }
                $rowMap[$col] = $value
            }
            if ($rowMap.Count -gt 0) { $rows += $rowMap }
        }

        $dataRows = @()
        $start = 0
        if ($rows.Count -gt 0) {
            $first = (($rows[0].Values | ForEach-Object { [string]$_ }) -join " ")
            if (([string]$rows[0]["A"]) -notmatch "\d" -and ([string]$rows[0]["C"]) -notmatch "\d") { $start = 1 }
        }

        for ($i = $start; $i -lt $rows.Count; $i++) {
            $r = $rows[$i]
            $item = [ordered]@{
                index = [string]$r["A"]
                time = [string]$r["B"]
                duration = [string]$r["C"]
                shot = [string]$r["D"]
                action = [string]$r["F"]
                audio = [string]$r["G"]
                englishVo = [string]$r["H"]
                chinese = [string]$r["I"]
            }
            $joined = ($item.Values -join "").Trim()
            if ($joined) { $dataRows += [pscustomobject]$item }
        }
        return $dataRows
    } finally {
        if ($archive) { $archive.Dispose() }
        Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue
    }
}

function Read-DocxText {
    param([byte[]]$Bytes)
    $temp = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllBytes($temp, $Bytes)
    $archive = $null
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($temp)
        $xml = Get-ZipText $archive "word/document.xml"
        if (-not $xml) { throw "No document.xml found in Word file." }
        $paragraphs = [regex]::Matches($xml, "<w:p[\s\S]*?</w:p>") | ForEach-Object {
            $texts = [regex]::Matches($_.Value, "<w:t[^>]*>([\s\S]*?)</w:t>") | ForEach-Object {
                ConvertFrom-XmlText $_.Groups[1].Value
            }
            ($texts -join "")
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        return ($paragraphs -join "`n")
    } finally {
        if ($archive) { $archive.Dispose() }
        Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue
    }
}

function Get-DurationSeconds {
    param($Row)
    $raw = ([string]$Row.duration).Trim()
    if ($raw -match "(\d+(?:\.\d+)?)") { return [double]$Matches[1] }
    $time = ([string]$Row.time).Trim()
    if ($time -match "(\d+):(\d+)\s*\p{Pd}\s*(\d+):(\d+)") {
        $a = ([int]$Matches[1] * 60) + [int]$Matches[2]
        $b = ([int]$Matches[3] * 60) + [int]$Matches[4]
        if ($b -gt $a) { return [double]($b - $a) }
    }
    return 4.0
}

function Format-StoryboardRows {
    param($Rows)
    $lines = @()
    foreach ($row in $Rows) {
        $lines += "Index: $($row.index)"
        $lines += "Time: $($row.time)"
        $lines += "Duration: $($row.duration)"
        $lines += "Shot and camera: $($row.shot)"
        $lines += "Visual action and rhythm: $($row.action)"
        $lines += "SFX / BGM: $($row.audio)"
        $lines += "English VO: $($row.englishVo)"
        $lines += "Chinese reference: $($row.chinese)"
        $lines += ""
    }
    $lines -join "`n"
}

function New-StoryboardGroups {
    param($Rows)
    $groups = @()
    $i = 0
    while ($i -lt $Rows.Count) {
        $row = $Rows[$i]
        $duration = Get-DurationSeconds $row
        if ($duration -gt 15) {
            $count = [Math]::Ceiling($duration / 4.0)
            for ($part = 0; $part -lt $count; $part++) {
                $start = $part * 4
                $len = [Math]::Min(4, $duration - $start)
                $groups += [pscustomobject]@{
                    title = "Shot $($row.index) split part $($part + 1) of $count"
                    rows = @($row)
                    totalSeconds = $len
                    note = "Original shot is longer than 15 seconds. Split this source content into a short-video shot no longer than 4 seconds. This part covers approximately $start to $([Math]::Round($start + $len, 1)) seconds."
                }
            }
            $i++
            continue
        }

        $selected = @($row)
        $total = $duration
        for ($j = 1; $j -lt 3 -and ($i + $j) -lt $Rows.Count; $j++) {
            $next = $Rows[$i + $j]
            $nextDuration = Get-DurationSeconds $next
            if (($total + $nextDuration) -le 15) {
                $selected += $next
                $total += $nextDuration
            } else {
                break
            }
        }

        $note = "Use the selected continuous storyboard rows to generate one prompt. Total duration must not exceed 15 seconds."
        if ($total -gt 6) {
            $note += " Because total duration is over 6 seconds, rebuild it into multiple micro-shots no longer than 4 seconds each, following Douyin short drama and YouTube viral short-video rhythm."
        }
        $groups += [pscustomobject]@{
            title = "Rows $($selected[0].index)-$($selected[$selected.Count - 1].index)"
            rows = $selected
            totalSeconds = $total
            note = $note
        }
        $i += $selected.Count
    }
    $groups
}

function New-ExcelGroupPrompt {
    param($Group)
    $rowsText = Format-StoryboardRows $Group.rows
    $timelineHeading = Get-Cn "timeline"
    $audioHeading = Get-Cn "audio"
    $bgmHeading = Get-Cn "bgm"
    $limitsHeading = Get-Cn "limits"
    $requirementsHeading = Get-Cn "requirements"
    $professionalRules = Get-ProfessionalPromptRules
    @"
You are Zhimengshi Mode A: SEEDANCE 2.0 Professional Prompt mode.

Task: Generate one SEEDANCE 2.0 prompt from the selected Excel storyboard rows.

Output language: Chinese, with necessary English video-generation terms.

Rules:
- The final prompt duration must be no more than 15 seconds.
- If the selected storyboard rows contain explicit durations, the final prompt duration must equal their total duration. Do not stretch to 12 seconds or 15 seconds.
- This is one prompt in a batch. The full batch must cover every storyboard row from the Excel file. Do not ignore later rows when the complete video is longer than 15 seconds.
- If the group duration is over 6 seconds, split the timeline into micro-shots no longer than 4 seconds each.
- If any row contains dialogue, especially dialogue marked by "character name + colon", check whether the row duration is enough at 2.5 to 3 Chinese characters per second plus key action, camera movement, pauses, and reaction beats. If not enough, split or redistribute the row into more realistic micro-shots while preserving the selected group's total duration.
- Follow Douyin short drama and YouTube viral short-video rhythm: strong hook, quick visual changes, clear emotional beat, no slow empty shot.
- Preserve the original storyboard meaning. Do not add unrelated plot.
- Do not output analysis notes. Do not output Markdown numbering such as "1." or "2.". Output the final prompt only.
- Do not say "ok", "received", "I will", or any conversational preface.
- Do not output Markdown symbols such as ###, **, or code fences.
- Use these exact section headings:
$timelineHeading
$audioHeading
$bgmHeading
$limitsHeading
$requirementsHeading

$professionalRules

Group title: $($Group.title)
Group total seconds: $($Group.totalSeconds)
Processing note: $($Group.note)

Source storyboard rows:
$rowsText
"@
}

function New-WordFilePrompt {
    param([string]$Mode, [string]$Text)
    if ($Mode -eq "A") {
        $durationPlan = Get-SourceDurationPlan $Text
        $dialogueTimingPlan = Get-DialogueTimingPlan $Text
        $timelineHeading = Get-Cn "timeline"
        $audioHeading = Get-Cn "audio"
        $bgmHeading = Get-Cn "bgm"
        $limitsHeading = Get-Cn "limits"
        $requirementsHeading = Get-Cn "requirements"
        $professionalRules = Get-ProfessionalPromptRules
        return @"
You are Zhimengshi Mode A: SEEDANCE 2.0 Professional Prompt mode.

Task: The user uploaded a Word novel/script document. Generate SEEDANCE 2.0 professional prompts from the document.

Output language: Chinese, with necessary English video-generation terms.

Core workflow:
The app itself does not analyze the plot locally. You, the external AI model, must read the Word source text, the rules, the reference example, and the output format together, then generate the final prompt according to these requirements.

Rules:
- Do not say "ok", "received", "I will", or any conversational preface.
- Do not output analysis notes.
- Do not output Markdown symbols such as ###, **, or code fences.
- Do not output bracket placeholders such as [Opening paragraph].
- First internally convert the full Word document into a complete storyboard table, but do not output that table in the final result. The internal storyboard must cover all scenes and all usable content in the document, not only the first 15 seconds.
- If the source document explicitly contains shot durations, the combined duration of all generated prompts must equal the explicit source total duration.
- If the source document does not contain explicit time, assign reasonable storyboard durations according to natural Mandarin dialogue timing, key actions, camera movement, reactions, and short-video rhythm, then use the storyboard total duration as the total duration to cover.
- If the complete storyboard total duration is over 15 seconds, split the final result into multiple complete SEEDANCE 2.0 prompts. Each single prompt should be no more than 15 seconds, and all prompts combined must cover the full storyboard duration.
- If the source document is longer than 1000 characters, do not summarize it into one 15-second prompt. Generate a full storyboard for the complete document, then output multiple prompts as needed.
- If the complete storyboard total duration is 15 seconds or less, output one complete prompt matching that duration.
- Never generate only the first 15 seconds when the document contains more scenes.
- Every generated Prompt must be a full professional SEEDANCE prompt, not just a storyboard row. Each Prompt must contain: style paragraph, storyboard section, Audio section, BGM section, generation limits section, requirements section.
- For multiple prompts, use this structure exactly: Prompt 1, complete professional prompt; Prompt 2, complete professional prompt; continue until the full Word document is covered.
- Do not output a separate analysis table before the prompts.
- Any timeline longer than 6 seconds should be rebuilt into micro-shots no longer than 4 seconds each.
- Use short-video rhythm suitable for Douyin short dramas and YouTube viral shorts.
- Output final prompt content only. If multiple prompts are needed, label them clearly as Prompt 1, Prompt 2, Prompt 3, etc.

$professionalRules

$durationPlan

$dialogueTimingPlan

Reference prompt example:
$(Get-SeedanceAExample)

Use these exact section headings:
$timelineHeading
$audioHeading
$bgmHeading
$limitsHeading
$requirementsHeading

Required output flow:
1. Internally create a complete storyboard table for the entire Word document.
2. Internally calculate or infer the storyboard total duration.
3. Output only the complete SEEDANCE 2.0 prompts.
4. Generate as many complete prompts as needed so the combined duration equals the storyboard total duration.
5. Each prompt must use the section headings listed above.

Source text:
$Text
"@
    }

    $professionalRules = Get-ProfessionalPromptRules
    $masterRules = Get-MasterPromptRules
    @"
You are Zhimengshi Mode B: SEEDANCE 2.0 Master Prompt mode, specialized for dialogue scenes.

Task: The user uploaded a Word novel/script document. Internally build the complete Professional Mode storyboard skeleton for the full document, then add Master Mode dialogue performance analysis, then output only master-level prompts that cover the full document.

Output language: Chinese, with necessary English video-generation terms.

Must follow:
- Do not say "ok", "received", "I will", or any conversational preface.
- Do not output Markdown symbols such as ###, **, or code fences.
- First internally create a complete storyboard table for the full document, but never output the raw table in the final result.
- Then internally analyze main speaking characters: count, name, identity, personality, speaking style, current emotion, conflict position.
- Never output "storyboard table", "main speaking character analysis", character tables, Markdown tables, or analysis reports.
- The final answer must start directly with "Prompt 1".

Professional Mode rules that must be preserved:
$professionalRules

$masterRules

- The storyboard must cover the full Word document, not only the first 15 seconds.
- If the complete storyboard total duration is over 15 seconds, split the final master-level dialogue prompts into multiple complete prompts. Each single prompt should be no more than 15 seconds, and all prompts combined must cover the full storyboard duration.
- Dialogue shot switches must preserve line continuity and natural semantic pauses.
- After one character speaks a line under 4 seconds, provide listener reaction shots for other key characters.
- Include shot size, camera movement, dialogue, tone, eyes, facial expression, action, micro-performance, subtext, head direction, gaze direction, counterpart position, and composition.
- The final output must be master-level dialogue performance prompts, not a table-first report and not ordinary paragraph summaries.
- Each timed segment must contain concrete scene/action content inherited from Professional Mode before acting details. Do not output only eye, tone, subtext, or micro-expression details.
- Output pure Chinese. All field labels and all performance descriptions must be Chinese. Do not use English labels such as Shot design, Segment, Dialogue, Tone, Eyes, Facial expression, Subtext, Listener reaction.
- Each Prompt is an independent Seedance video. The Prompt title may show the global source time range, for example "提示词2（全局时间：15-30秒）", but all internal segment times inside that Prompt must restart from 0 seconds, for example "第一段（0-4秒）", "第二段（4-8秒）". Never write internal segment times like 15-19 seconds.
- Each master prompt must follow this performance structure:
  提示词N（全局时间：start-end秒，供用户识别原剧本位置；本条提示词内部时间从0秒开始）
  镜头设计：
  - 景别：
  - 镜头运动：
  - 构图：
  - 人物朝向与视线：
  第一段（0-x秒）：中文标题
  - 场景/构图：
  - 核心动作：
  - 台词：
  - 语气：
  - 关键词发音：
  - 眼神：
  - 表情：
  - 动作/微表演：
  - 潜台词：
  - 听者反应：
  第二段（x-y秒）：中文标题
  - 场景/构图：
  - 核心动作：
  - 台词：
  - 语气：
  - 关键词发音：
  - 眼神：
  - 表情：
  - 动作/微表演：
  - 潜台词：
  - 听者反应：
  第三段（y-z秒）：中文标题
  - 场景/构图：
  - 核心动作：
  - 台词：
  - 语气：
  - 关键词发音：
  - 眼神：
  - 表情：
  - 动作/微表演：
  - 潜台词：
  - 听者反应：
- For every dialogue line, analyze keyword delivery. Describe how important words are spoken: weight, pause, pitch, speed, breath.
- For every listener reaction, write no-dialogue performance: gaze movement, eyelid change, mouth corner, breathing, hand or body micro-action, hidden psychology.
- Do not write generic lines like "the character looks serious". Use detailed performance instructions like the user's master prompt examples.

Source text:
$Text
"@
}

function New-ExcelMasterPrompt {
    param($Rows)
    $rowsText = Format-StoryboardRows $Rows
    $professionalRules = Get-ProfessionalPromptRules
    $masterRules = Get-MasterPromptRules
    @"
You are Zhimengshi Mode B: SEEDANCE 2.0 Master Prompt mode, specialized for dialogue scenes.

Task: The user uploaded an Excel storyboard table. Analyze all rows, identify the main speaking characters and their personalities, then select suitable continuous rows to generate master-level dialogue prompts.

Output language: PURE CHINESE.

Rules:
- Do not output any conversational preface, such as "好的", "收到", "我已分析", "基于规则", or "以下是".
- Do not output analysis, explanation, storyboard table, character analysis, Markdown table, or separator lines.
- The final answer must start directly with "提示词1" or "提示词1（全局时间：...）".
- Output pure Chinese. All labels and performance descriptions must be Chinese.
- Do not output English paragraphs or English labels. Forbidden words include: Prompt, Master Prompt, SCENE START, Shot, INSERT SHOT, Close-up, Medium Shot, Dialogue, Tone, Eyes, Subtext, EYE-LINE, SUBJECT, BGM description in English.
- The only English allowed is the fixed model name "SEEDANCE 2.0" when necessary.

$masterRules

Professional Mode rules that must be preserved:
$professionalRules

- Cover every source storyboard row. For each prompt, select continuous neighboring rows with total duration no more than 15 seconds; if all rows exceed 15 seconds combined, output multiple complete prompts until every row is covered.
- Dialogue continuity is more important than mechanical row splitting.
- Do not cut a phrase or unfinished sentence in the middle.
- Add listener reaction shots after a speaker finishes a short line.
- Include shot size, camera movement, tone, eyes, facial expression, micro-performance, subtext, eye-line consistency, and composition.
- Each prompt must be an independent SEEDANCE video prompt. The title may show a global source range, but every internal segment must restart from 0 seconds.
- Required structure for every prompt:
  提示词1（全局时间：start-end秒；本条提示词内部时间从0秒开始）
  镜头设计：
  - 景别：
  - 镜头运动：
  - 构图：
  - 人物朝向与视线：
  第一段（0-x秒）：中文小标题
  - 台词：
  - 语气：
  - 关键词发音：
  - 眼神：
  - 表情：
  - 动作/微表演：
  - 潜台词：
  - 听者反应：
  第二段（x-y秒）：中文小标题
  - 台词：
  - 语气：
  - 关键词发音：
  - 眼神：
  - 表情：
  - 动作/微表演：
  - 潜台词：
  - 听者反应：
- If there is no dialogue in a segment, write "台词：无台词，纯反应", but still describe eyes, facial expression, action, subtext, and listener reaction.

Source storyboard rows:
$rowsText
"@
}

function New-DocxBase64 {
    param([string]$Title, [string[]]$Sections)
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    $docx = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString() + ".docx")
    try {
        New-Item -ItemType Directory -Path (Join-Path $tempDir "_rels") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempDir "word") -Force | Out-Null

        @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
'@ | Set-Content -LiteralPath (Join-Path $tempDir "[Content_Types].xml") -Encoding UTF8

        @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
'@ | Set-Content -LiteralPath (Join-Path $tempDir "_rels\.rels") -Encoding UTF8

        $paragraphs = @()
        $allLines = @($Title) + @("") + ($Sections -join "`n`n---`n`n").Split("`n")
        foreach ($line in $allLines) {
            $safe = ConvertTo-XmlText $line
            $paragraphs += "<w:p><w:r><w:t xml:space=""preserve"">$safe</w:t></w:r></w:p>"
        }
        $docXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    $($paragraphs -join "`n    ")
    <w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>
  </w:body>
</w:document>
"@
        $docXml | Set-Content -LiteralPath (Join-Path $tempDir "word\document.xml") -Encoding UTF8
        [System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, $docx)
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($docx))
    } finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $docx -Force -ErrorAction SilentlyContinue
    }
}

function New-PreviewText {
    param([string]$Text)
    $clean = ([string]$Text).Trim()
    if ($clean.Length -le 1000) { return $clean }
    return $clean.Substring(0, 1000) + "`n`n" + (Get-PreviewDownloadNotice)
}

function Get-PreviewDownloadNotice {
    Join-CodePoints @(
        0x005B,0x9884,0x89C8,0x4EC5,0x663E,0x793A,0x524D,0x0031,0x0030,0x0030,0x0030,0x5B57,0x7B26,
        0xFF0C,0x5B8C,0x6574,0x6279,0x91CF,0x63D0,0x793A,0x8BCD,0x8BF7,0x70B9,0x51FB,0x201C,
        0x4E0B,0x8F7D,0x0020,0x0057,0x006F,0x0072,0x0064,0x201D,0x3002,0x005D
    )
}

function Get-SafeFileName {
    param([string]$Name)
    $safe = ([string]$Name).Trim()
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = "Zhimengshi" }
    $safe = [regex]::Replace($safe, '[\\/:*?"<>|]', "_")
    $safe = [regex]::Replace($safe, "\s+", " ")
    return $safe.Trim()
}

function Get-ModeSuffix {
    param([string]$Mode)
    $pro = Join-CodePoints @(0x4E13,0x4E1A)
    $master = Join-CodePoints @(0x5927,0x5E08)
    $prompt = Join-CodePoints @(0x63D0,0x793A,0x8BCD)
    $modeText = if ($Mode -eq "B") { $master } else { $pro }
    return "SEEDANCE$modeText$prompt.docx"
}

function Get-DocumentTitle {
    param([string]$FileName, [string]$Text)
    $left = [char]0x300A
    $right = [char]0x300B
    $quoted = [regex]::Match($Text, [regex]::Escape([string]$left) + "([^" + [regex]::Escape([string]$right) + "]{1,60})" + [regex]::Escape([string]$right))
    if ($quoted.Success) {
        return Get-SafeFileName ($left + $quoted.Groups[1].Value.Trim() + $right)
    }

    $lines = $Text -split "\r?\n" | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ }
    if ($lines.Count -gt 0) {
        $first = $lines[0]
        if ($first.Length -le 60 -and $first -notmatch "[,，。；;]") {
            return Get-SafeFileName $first
        }
    }

    return Get-SafeFileName ([System.IO.Path]::GetFileNameWithoutExtension($FileName))
}

function Get-DownloadName {
    param([string]$FileName, [string]$Mode, [string]$Text)
    $title = Get-DocumentTitle -FileName $FileName -Text $Text
    return (Get-SafeFileName ($title + (Get-ModeSuffix $Mode)))
}

function Invoke-FileGeneration {
    param($Settings, $Body)
    $fileName = [string]$Body.fileName
    $mode = [string]$Body.mode
    $bytes = [Convert]::FromBase64String([string]$Body.base64)
    $ext = [System.IO.Path]::GetExtension($fileName).ToLowerInvariant()

    if ($ext -eq ".xlsx") {
        $rows = Read-XlsxRows $bytes
        if ($rows.Count -eq 0) { throw "No usable storyboard rows found in Excel file." }
        $allRowsText = Format-StoryboardRows $rows
        $sections = @()
        if ($mode -eq "A") {
            $groups = New-StoryboardGroups $rows
            $counter = 1
            foreach ($group in $groups) {
                $prompt = New-ExcelGroupPrompt $group
                $content = Invoke-AI $Settings $prompt
                $maxEnd = Get-MaxTimelineEndSecond $content
                if ($maxEnd -gt ([double]$group.totalSeconds + 0.05)) {
                    $content = Invoke-AI $Settings (New-DurationCorrectionPrompt -OriginalPrompt $prompt -BadOutput $content -TotalSeconds ([double]$group.totalSeconds))
                }
                $sections += "Prompt $counter - $($group.title)`n$content"
                $counter++
            }
        } else {
            $prompt = New-ExcelMasterPrompt $rows
            $content = Invoke-AI $Settings $prompt
            $content = Repair-MasterOutput -Settings $Settings -Prompt $prompt -Content $content
            $sections += $content
        }
        $fullContent = ($sections -join "`n`n---`n`n")
        $downloadName = Get-DownloadName -FileName $fileName -Mode $mode -Text ($allRowsText + "`n" + $fullContent)
        $docTitle = [System.IO.Path]::GetFileNameWithoutExtension($downloadName)
        $docBase64 = New-DocxBase64 $docTitle $sections
        return @{
            ok = $true
            content = (New-PreviewText $fullContent)
            downloadName = $downloadName
            downloadBase64 = $docBase64
        }
    }

    if ($ext -eq ".docx") {
        $text = Read-DocxText $bytes
        if ([string]::IsNullOrWhiteSpace($text)) { throw "No readable text found in Word file." }
        $prompt = New-WordFilePrompt -Mode $mode -Text $text
        $content = Invoke-AI $Settings $prompt
        if ($mode -eq "B") {
            $content = Repair-MasterOutput -Settings $Settings -Prompt $prompt -Content $content
            if (Test-ProfessionalOutputMissingDialogue -SourceText $text -OutputText $content) {
                $content = Invoke-AI $Settings (New-MasterCoverageCorrectionPrompt -OriginalPrompt $prompt -BadOutput $content -SourceText $text)
                $content = Repair-MasterOutput -Settings $Settings -Prompt $prompt -Content $content
            }
            if ((Test-ProfessionalOutputTooShortForDialogue -SourceText $text -OutputText $content) -or (Test-ProfessionalSegmentTooShortForDialogue -SourceText $text -OutputText $content)) {
                $content = Invoke-AI $Settings (New-MasterDialogueTimingCorrectionPrompt -OriginalPrompt $prompt -BadOutput $content -SourceText $text)
                $content = Repair-MasterOutput -Settings $Settings -Prompt $prompt -Content $content
            }
        }
        if ($mode -eq "A") {
            $explicitTotal = Get-ExplicitTotalSeconds $text
            if ($explicitTotal -ne $null -and $explicitTotal -le 15) {
                $maxEnd = Get-MaxTimelineEndSecond $content
                if ($maxEnd -gt ($explicitTotal + 0.05)) {
                    $content = Invoke-AI $Settings (New-DurationCorrectionPrompt -OriginalPrompt $prompt -BadOutput $content -TotalSeconds $explicitTotal)
                }
            }
            if (Test-ProfessionalOutputMissingDialogue -SourceText $text -OutputText $content) {
                $content = Invoke-AI $Settings (New-ProfessionalDialogueCorrectionPrompt -OriginalPrompt $prompt -BadOutput $content -SourceText $text)
            }
            if (Test-ProfessionalOutputTooShortForDialogue -SourceText $text -OutputText $content) {
                $content = Invoke-AI $Settings (New-ProfessionalDialogueTimingCorrectionPrompt -OriginalPrompt $prompt -BadOutput $content -SourceText $text)
            }
            if (Test-ProfessionalSegmentTooShortForDialogue -SourceText $text -OutputText $content) {
                $content = Invoke-AI $Settings (New-ProfessionalSegmentTimingCorrectionPrompt -OriginalPrompt $prompt -BadOutput $content -SourceText $text)
            }
            if (Test-ProfessionalPromptOver15Seconds -OutputText $content) {
                $content = Invoke-AI $Settings (New-ProfessionalOver15CorrectionPrompt -OriginalPrompt $prompt -BadOutput $content -SourceText $text)
            }
            if (Test-ProfessionalSegmentTooShortForDialogue -SourceText $text -OutputText $content) {
                $content = Invoke-AI $Settings (New-ProfessionalSegmentTimingCorrectionPrompt -OriginalPrompt $prompt -BadOutput $content -SourceText $text)
            }
        }
        $downloadName = Get-DownloadName -FileName $fileName -Mode $mode -Text $text
        $docTitle = [System.IO.Path]::GetFileNameWithoutExtension($downloadName)
        $docBase64 = New-DocxBase64 $docTitle @($content)
        return @{
            ok = $true
            content = (New-PreviewText $content)
            downloadName = $downloadName
            downloadBase64 = $docBase64
        }
    }

    throw "Only .xlsx and .docx uploads are supported in this version."
}

$listener = [System.Net.HttpListener]::new()
$listenHost = if ($HostName -eq "*" -or $HostName -eq "0.0.0.0" -or $HostName -eq "+") { "+" } else { $HostName }
$prefix = "http://$listenHost`:$Port/"
$listener.Prefixes.Add($prefix)
$listener.Start()
Write-Host "Zhimengshi server started: $prefix"
Write-Host "Local URL: http://localhost:$Port/"
if ($listenHost -eq "+") {
    foreach ($ip in Get-LocalIPv4Addresses) {
        Write-Host "LAN URL: http://$ip`:$Port/"
    }
}

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    try {
        $path = $request.Url.AbsolutePath

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/settings") {
            Write-Json $response 200 (Get-Settings)
            continue
        }

        if ($request.HttpMethod -eq "POST" -and $path -eq "/api/settings") {
            $body = Read-RequestJson $request
            Save-Settings $body
            Write-Json $response 200 (Get-Settings)
            continue
        }

        if ($request.HttpMethod -eq "DELETE" -and $path -eq "/api/settings") {
            Clear-Settings
            Write-Json $response 200 (Get-Settings)
            continue
        }

        if ($request.HttpMethod -eq "POST" -and $path -eq "/api/test-model") {
            $settings = Get-Settings -IncludeKey
            if (-not $settings.hasApiKey) { throw "Please save model settings first." }
            $null = Invoke-AI $settings "Reply with exactly: OK"
            Write-Json $response 200 @{ ok = $true; content = (Get-TestSuccessMessage) }
            continue
        }

        if ($request.HttpMethod -eq "POST" -and $path -eq "/api/generate-short") {
            $settings = Get-Settings -IncludeKey
            if (-not $settings.hasApiKey) { throw "Please finish model settings first." }
            $body = Read-RequestJson $request
            $mode = [string]$body.mode
            $sourceText = [string]$body.text
            $prompt = New-GenerationPrompt -Mode $mode -Text $sourceText
            $content = Invoke-AI $settings $prompt
            if ($mode -eq "B") {
                $content = Repair-MasterOutput -Settings $settings -Prompt $prompt -Content $content
                if (Test-ProfessionalOutputMissingDialogue -SourceText $sourceText -OutputText $content) {
                    $content = Invoke-AI $settings (New-MasterCoverageCorrectionPrompt -OriginalPrompt $prompt -BadOutput $content -SourceText $sourceText)
                    $content = Repair-MasterOutput -Settings $settings -Prompt $prompt -Content $content
                }
                if ((Test-ProfessionalOutputTooShortForDialogue -SourceText $sourceText -OutputText $content) -or (Test-ProfessionalSegmentTooShortForDialogue -SourceText $sourceText -OutputText $content)) {
                    $content = Invoke-AI $settings (New-MasterDialogueTimingCorrectionPrompt -OriginalPrompt $prompt -BadOutput $content -SourceText $sourceText)
                    $content = Repair-MasterOutput -Settings $settings -Prompt $prompt -Content $content
                }
            }
            if ($mode -eq "A") {
                $explicitTotal = Get-ExplicitTotalSeconds $sourceText
                if ($explicitTotal -ne $null) {
                    $maxEnd = Get-MaxTimelineEndSecond $content
                    if ($maxEnd -gt ($explicitTotal + 0.05)) {
                        $content = Invoke-AI $settings (New-DurationCorrectionPrompt -OriginalPrompt $prompt -BadOutput $content -TotalSeconds $explicitTotal)
                    }
                }
                if (Test-ProfessionalOutputMissingDialogue -SourceText $sourceText -OutputText $content) {
                    $content = Invoke-AI $settings (New-ProfessionalDialogueCorrectionPrompt -OriginalPrompt $prompt -BadOutput $content -SourceText $sourceText)
                }
                if (Test-ProfessionalOutputTooShortForDialogue -SourceText $sourceText -OutputText $content) {
                    $content = Invoke-AI $settings (New-ProfessionalDialogueTimingCorrectionPrompt -OriginalPrompt $prompt -BadOutput $content -SourceText $sourceText)
                }
                if (Test-ProfessionalSegmentTooShortForDialogue -SourceText $sourceText -OutputText $content) {
                    $content = Invoke-AI $settings (New-ProfessionalSegmentTimingCorrectionPrompt -OriginalPrompt $prompt -BadOutput $content -SourceText $sourceText)
                }
                if (Test-ProfessionalPromptOver15Seconds -OutputText $content) {
                    $content = Invoke-AI $settings (New-ProfessionalOver15CorrectionPrompt -OriginalPrompt $prompt -BadOutput $content -SourceText $sourceText)
                }
                if (Test-ProfessionalSegmentTooShortForDialogue -SourceText $sourceText -OutputText $content) {
                    $content = Invoke-AI $settings (New-ProfessionalSegmentTimingCorrectionPrompt -OriginalPrompt $prompt -BadOutput $content -SourceText $sourceText)
                }
            }
            Write-Json $response 200 @{ ok = $true; content = $content }
            continue
        }

        if ($request.HttpMethod -eq "POST" -and $path -eq "/api/generate-file") {
            $settings = Get-Settings -IncludeKey
            if (-not $settings.hasApiKey) { throw "Please finish model settings first." }
            $body = Read-RequestJson $request
            $result = Invoke-FileGeneration $settings $body
            Write-Json $response 200 $result
            continue
        }

        $relative = if ($path -eq "/") { "index.html" } else { [uri]::UnescapeDataString($path.TrimStart("/")) }
        $filePath = [System.IO.Path]::GetFullPath((Join-Path $PublicDir $relative))
        $publicFull = [System.IO.Path]::GetFullPath($PublicDir)
        if (-not $filePath.StartsWith($publicFull)) {
            Write-Json $response 403 @{ ok = $false; error = "Forbidden" }
            continue
        }
        if (-not (Test-Path -LiteralPath $filePath) -or (Get-Item -LiteralPath $filePath).PSIsContainer) {
            Write-Json $response 404 @{ ok = $false; error = "Not found" }
            continue
        }
        Write-StaticFile $response $filePath
    } catch {
        Write-Json $response 400 @{ ok = $false; error = $_.Exception.Message }
    }
}
