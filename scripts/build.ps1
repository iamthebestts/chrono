Get-Content .env | ForEach-Object {
    if ($_ -match "^\s*([^#][^=]+)=(.+)$") {
        [Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), "Process")
    }
}
lute build