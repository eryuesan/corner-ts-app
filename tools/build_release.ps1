param(
    [Parameter(Mandatory)][string]$Notes,
    [string]$OutputDirectory = (Join-Path ([IO.Path]::GetTempPath()) 'corner-ts-releases')
)
$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path $PSScriptRoot -Parent) '数据标准处理程序'
$code = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $source 'target_strength_app.m')
$guide = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $source '声学目标强度分析App使用指南.md')
$match = [regex]::Match($code, "(?m)^versionTag = '(v[0-9]+(?:\.[0-9]+){1,2})';")
if (!$match.Success) { throw 'Cannot determine the App release version.' }
$version = $match.Groups[1].Value
$dest = Join-Path $OutputDirectory $version
New-Item -ItemType Directory -Path $dest -ErrorAction Stop | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $dest 'corner-ts-app.zip'
$archive = [IO.Compression.ZipFile]::Open($zip,'Create',[Text.Encoding]::UTF8)
try {
    # 已安装的 v2.5/v2.6 按固定文件名校验更新包，并通过旧函数名启动。
    if ($code -notmatch '\Afunction target_strength_app\r?\n') { throw 'Unexpected App entry point.' }
    $contents = [ordered]@{
        'corner_ts_app.m' = $code -replace '\Afunction target_strength_app', 'function corner_ts_app'
        '角反射体TS处理App使用指南.md' = $guide.Replace('target_strength_app.m','corner_ts_app.m')
    }
    foreach ($name in $contents.Keys) {
        $writer = [IO.StreamWriter]::new($archive.CreateEntry($name).Open(),[Text.UTF8Encoding]::new($false))
        try { $writer.Write($contents[$name]) } finally { $writer.Dispose() }
    }
    $notesFile = '脉冲维高通滤波逐行讲解.md'
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $archive,(Join-Path $source $notesFile),$notesFile,'Optimal') | Out-Null
} finally { $archive.Dispose() }
$manifest = [ordered]@{version=$version; notes=$Notes; sha256=(Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()}
[IO.File]::WriteAllText((Join-Path $dest 'corner-ts-update.json'),($manifest | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
Get-ChildItem -LiteralPath $dest | Select-Object Name,Length,FullName
