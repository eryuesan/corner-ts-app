param(
    [Parameter(Mandatory)][string]$Notes,
    [string]$OutputDirectory = (Join-Path ([IO.Path]::GetTempPath()) 'corner-ts-releases')
)
$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path $PSScriptRoot -Parent) '数据标准处理程序'
$files = 'corner_ts_app.m','角反射体TS处理App使用指南.md','脉冲维高通滤波逐行讲解.md'
$code = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $source $files[0])
$match = [regex]::Match($code, "(?m)^versionTag = '(v[0-9]+(?:\.[0-9]+){1,2})';")
if (!$match.Success) { throw 'Cannot determine the App release version.' }
$version = $match.Groups[1].Value
$dest = Join-Path $OutputDirectory $version
New-Item -ItemType Directory -Path $dest -ErrorAction Stop | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $dest 'corner-ts-app.zip'
$archive = [IO.Compression.ZipFile]::Open($zip,'Create',[Text.Encoding]::UTF8)
try {
    foreach ($name in $files) {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive,(Join-Path $source $name),$name,'Optimal') | Out-Null
    }
} finally { $archive.Dispose() }
$manifest = [ordered]@{version=$version; notes=$Notes; sha256=(Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()}
[IO.File]::WriteAllText((Join-Path $dest 'corner-ts-update.json'),($manifest | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
Get-ChildItem -LiteralPath $dest | Select-Object Name,Length,FullName
