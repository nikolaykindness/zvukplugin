# Build Zvuk LMS plugin zip and generate repository.xml for Additional Repositories.
# Usage: .\scripts\build-release.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ConfigPath = Join-Path $Root 'repo.config.json'
$PluginSrc = Join-Path $Root 'Plugins\Zvuk'
$DistDir = Join-Path $Root 'dist'

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

if (-not (Test-Path $DistDir)) {
	New-Item -ItemType Directory -Path $DistDir | Out-Null
}

if (Test-Path $zipPath) {
	Remove-Item $zipPath -Force
}

# LMS expects the plugin folder "Zvuk" at the root of the zip archive.
Compress-Archive -Path $PluginSrc -DestinationPath $zipPath -CompressionLevel Optimal

$sha = (Get-FileHash -Path $zipPath -Algorithm SHA1).Hash.ToLower()
$user = $config.github_user
$repo = $config.github_repo
$tag = "v$version"

$zipUrl = "https://github.com/$user/$repo/releases/download/$tag/$zipName"
$repoUrl = "https://raw.githubusercontent.com/$user/$repo/main/repository.xml"

$repositoryXml = @"
<?xml version="1.0"?>
<extensions>
	<details>
		<title lang="EN">Zvuk Plugin Repository</title>
		<title lang="RU">Репозиторий плагина СберЗвук</title>
	</details>
	<plugins>
		<plugin name="Zvuk" version="$version" minTarget="7.9" maxTarget="*" category="musicservices">
			<title lang="EN">SberZvuk</title>
			<title lang="RU">СберЗвук</title>
			<desc lang="EN">Stream music from SberZvuk (zvuk.com) in Lyrion Music Server / Daphile.</desc>
			<desc lang="RU">Стриминг музыки из СберЗвук (zvuk.com) в Lyrion Music Server / Daphile.</desc>
			<changes lang="EN">Enable plugin by default after install and move settings template into LMS HTML path.</changes>
			<changes lang="RU">Плагин включается по умолчанию после установки, шаблон настроек перенесён в правильный HTML-путь LMS.</changes>
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
Write-Host "  SHA1: $sha"
Write-Host "  Repo: $repositoryPath"
Write-Host ""
Write-Host "Additional Repositories URL (for LMS):"
Write-Host "  $repoUrl"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Edit repo.config.json (github_user, email)"
Write-Host "  2. Re-run this script after config changes"
Write-Host "  3. git add repository.xml && git commit && git push"
Write-Host "  4. Create GitHub Release tag $tag and upload $zipName from dist\"
Write-Host ""
