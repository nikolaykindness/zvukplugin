# Build Zvuk LMS plugin zip and generate repository.xml for Additional Repositories.
# Usage: .\scripts\build-release.ps1
#
# LMS on Linux expects forward slashes inside the zip (Zvuk/install.xml), not Windows backslashes.
# strings.txt must use LF line endings; CRLF breaks string ID parsing in Slim::Utils::Strings.

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ConfigPath = Join-Path $Root 'repo.config.json'
$PluginSrc = Join-Path $Root 'Plugins\Zvuk'
$DistDir = Join-Path $Root 'dist'
$ReleasesDir = Join-Path $Root 'releases'

if (-not (Test-Path $DistDir)) {
	New-Item -ItemType Directory -Path $DistDir | Out-Null
}
if (-not (Test-Path $ReleasesDir)) {
	New-Item -ItemType Directory -Path $ReleasesDir | Out-Null
}

if (-not (Test-Path $ConfigPath)) {
	Write-Error "Missing repo.config.json in project root."
}
if (-not (Test-Path $PluginSrc)) {
	Write-Error "Missing Plugins\Zvuk directory."
}

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$version = $config.version
$zipName = "Zvuk-$version.zip"
$zipPath = Join-Path $DistDir $zipName
$releaseZipPath = Join-Path $ReleasesDir $zipName
$tag = "v$version"
$user = $config.github_user
$repo = $config.github_repo

function Normalize-PluginTextFiles {
	param([string]$SourceDir)

	$utf8NoBom = New-Object System.Text.UTF8Encoding $false
	$extensions = @('.txt', '.html', '.xml', '.pm')

	Get-ChildItem -Path $SourceDir -Recurse -File | Where-Object {
		$extensions -contains $_.Extension
	} | ForEach-Object {
		$text = [System.IO.File]::ReadAllText($_.FullName)
		$normalized = ($text -replace "`r`n", "`n") -replace "`r", "`n"
		if ($normalized -ne $text) {
			[System.IO.File]::WriteAllText($_.FullName, $normalized, $utf8NoBom)
		}
	}
}

function New-LmsPluginZip {
	param(
		[string]$SourceDir,
		[string]$DestinationZip,
		[string]$RootFolderName
	)

	Add-Type -AssemblyName System.IO.Compression
	Add-Type -AssemblyName System.IO.Compression.FileSystem

	$parent = Split-Path -Parent $DestinationZip
	if (-not (Test-Path $parent)) {
		New-Item -ItemType Directory -Path $parent | Out-Null
	}
	if (Test-Path $DestinationZip) {
		Remove-Item $DestinationZip -Force
	}

	$sourceRoot = (Resolve-Path $SourceDir).Path.TrimEnd('\')
	$zip = [System.IO.Compression.ZipFile]::Open(
		$DestinationZip,
		[System.IO.Compression.ZipArchiveMode]::Create
	)

	try {
		Get-ChildItem -Path $sourceRoot -Recurse -File | ForEach-Object {
			$relative = $_.FullName.Substring($sourceRoot.Length).TrimStart('\', '/')
			$entryName = ($RootFolderName + '/' + ($relative -replace '\\', '/'))
			[void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
				$zip,
				$_.FullName,
				$entryName,
				[System.IO.Compression.CompressionLevel]::Optimal
			)
		}
	}
	finally {
		$zip.Dispose()
	}
}

Normalize-PluginTextFiles -SourceDir $PluginSrc
New-LmsPluginZip -SourceDir $PluginSrc -DestinationZip $zipPath -RootFolderName 'Zvuk'
Copy-Item $zipPath $releaseZipPath -Force

$sha = (Get-FileHash -Path $zipPath -Algorithm SHA1).Hash.ToLower()

# jsDelivr works from Russia; GitHub release downloads often time out on Daphile.
$zipUrl = "https://cdn.jsdelivr.net/gh/$user/$repo@$tag/releases/$zipName"
$repoUrl = "https://cdn.jsdelivr.net/gh/$user/$repo@$tag/repository.xml"

$repositoryXml = @"
<?xml version="1.0"?>
<extensions>
	<details>
		<title lang="EN">Zvuk Plugin Repository</title>
	</details>
	<plugins>
		<plugin name="Zvuk" version="$version" minTarget="7.9" maxTarget="*" category="musicservices">
			<title lang="EN">SberZvuk</title>
			<desc lang="EN">Stream music from SberZvuk (zvuk.com) in Lyrion Music Server / Daphile.</desc>
			<changes lang="EN">Fix playback URLs, browse navigation, and stream auth headers.</changes>
			<creator>$($config.creator)</creator>
			<email>$($config.email)</email>
			<url>$zipUrl</url>
			<sha>$sha</sha>
		</plugin>
	</plugins>
</extensions>
"@

$repositoryPath = Join-Path $Root 'repository.xml'
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($repositoryPath, $repositoryXml, $utf8NoBom)
Copy-Item $repositoryPath (Join-Path $DistDir 'repository.xml') -Force

Write-Host ""
Write-Host "Build complete."
Write-Host "  Zip:  $zipPath"
Write-Host "  Release copy: $releaseZipPath"
Write-Host "  SHA1: $sha"
Write-Host "  Repo: $repositoryPath"
Write-Host ""
Write-Host "Additional Repositories URL (for LMS, use jsDelivr):"
Write-Host "  $repoUrl"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. git add repository.xml releases/ Plugins/ && git commit && git push"
Write-Host "  2. git tag $tag && git push origin $tag"
Write-Host "  3. Optional: upload $zipName to GitHub Release $tag"
Write-Host ""
