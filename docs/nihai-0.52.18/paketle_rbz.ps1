param($Src,$Out)
Add-Type -A System.IO.Compression
Add-Type -A System.IO.Compression.FileSystem
$src=(Resolve-Path $Src).Path
$fs=[IO.File]::Open($Out,[IO.FileMode]::CreateNew)
$zip=New-Object IO.Compression.ZipArchive($fs,[IO.Compression.ZipArchiveMode]::Create)
$files=Get-ChildItem -Path $src -Recurse -File | Sort-Object { $_.FullName.Substring($src.Length+1).Replace('\','/') }
foreach($f in $files){
  $name=$f.FullName.Substring($src.Length+1).Replace('\','/')
  [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$f.FullName,$name,[IO.Compression.CompressionLevel]::Optimal)
}
$zip.Dispose(); $fs.Dispose()
