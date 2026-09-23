param([string]$Ffmpeg = 'ffmpeg')

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$framePattern = Join-Path $projectRoot 'artifacts/block_war_selection/frame_%03d.png'
$outputDirectory = Join-Path $projectRoot 'docs/art/selection_motion'
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

function Export-PreviewGif([string]$filter, [string]$filename) {
    $palette = ',split[a][b];[a]palettegen=stats_mode=full[p];[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle'
    & $Ffmpeg -hide_banner -loglevel error -y -framerate 30 -i $framePattern `
        -filter_complex_threads 1 -filter_complex ($filter + $palette) `
        -frames:v 90 -loop 0 (Join-Path $outputDirectory $filename)
    if ($LASTEXITCODE -ne 0) {
        throw "GIF export failed: $filename"
    }
}

Export-PreviewGif 'scale=1200:1000:flags=lanczos' 'overview.gif'
for ($index = 0; $index -lt 6; $index++) {
    $clipX = ($index % 3) * 480
    $clipY = 84 + [math]::Floor($index / 3) * 500
    Export-PreviewGif ('crop=480:500:{0}:{1}' -f $clipX, $clipY) ('{0:00}.gif' -f ($index + 1))
}
Get-ChildItem -LiteralPath $outputDirectory -Filter '*.gif' | Select-Object Name,Length
