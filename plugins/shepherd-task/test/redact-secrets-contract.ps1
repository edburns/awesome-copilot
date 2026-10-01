# shepherd-task-version: 1.0.4

$ErrorActionPreference = 'Stop'

$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$redactor = Join-Path $testRoot '..\scripts\redact-secrets.ps1'
$tempRoot = Join-Path (
    [IO.Path]::GetTempPath()
) "shepherd-redaction-contract-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tempRoot | Out-Null

function Invoke-StreamingRedactor {
    param([string]$InputText)

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command pwsh).Source
    $startInfo.ArgumentList.Add('-NoProfile')
    $startInfo.ArgumentList.Add('-File')
    $startInfo.ArgumentList.Add($redactor)
    $startInfo.ArgumentList.Add('-')
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $process.StandardInput.Write($InputText)
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdout
        Stderr = $stderr
    }
}

try {
    $fakeStreamSecret = 'ghp_stream_secret_must_not_survive'
    $secondStreamSecret = 'sk-stream-secret-must-not-survive'
    $inputLines = @(
        '{"type":"start","token":"ghp_valid_secret"}',
        "not-json $fakeStreamSecret",
        '',
        "still-not-json $secondStreamSecret",
        '{"type":"result","data":{"status":"complete"}}'
    )
    $streamResult = Invoke-StreamingRedactor (
        ($inputLines -join [Environment]::NewLine) +
        [Environment]::NewLine
    )
    if ($streamResult.ExitCode -ne 0) {
        throw "Streaming redactor exited $($streamResult.ExitCode)."
    }
    $records = @(
        $streamResult.Stdout -split '\r?\n' |
            Where-Object { $_ } |
            ForEach-Object { $_ | ConvertFrom-Json -Depth 100 }
    )
    if (-not ($records | Where-Object {
        $_.type -eq 'start' -and $_.token -eq '[REDACTED]'
    })) {
        throw 'The valid leading record was not redacted.'
    }
    if (-not ($records | Where-Object {
        $_.type -eq 'shepherd.redaction_warning' -and
        $_.data.reason -eq 'invalid_jsonl_record' -and
        $_.data.line -eq 2 -and
        $_.data.byteCount -gt 0
    })) {
        throw 'The first malformed record was not replaced safely.'
    }
    if (-not ($records | Where-Object {
        $_.type -eq 'shepherd.redaction_warning' -and
        $_.data.reason -eq 'invalid_jsonl_record' -and
        $_.data.line -eq 4 -and
        $_.data.byteCount -gt 0
    })) {
        throw 'The second malformed record was not replaced safely.'
    }
    if (-not ($records | Where-Object {
        $_.type -eq 'result' -and $_.data.status -eq 'complete'
    })) {
        throw 'The terminal record after malformed input was lost.'
    }
    if ($streamResult.Stdout.Contains($fakeStreamSecret)) {
        throw 'The malformed input secret leaked into streaming output.'
    }
    if ($streamResult.Stdout.Contains($secondStreamSecret)) {
        throw 'The second malformed input secret leaked into streaming output.'
    }

    $logDirectory = Join-Path $tempRoot 'logs'
    New-Item -ItemType Directory -Path $logDirectory | Out-Null
    $jsonlPath = Join-Path $logDirectory 'session.jsonl'
    [IO.File]::WriteAllLines(
        $jsonlPath,
        @(
            '{"type":"before","password":"directory-secret"}',
            'malformed ghp_directory_secret_must_not_survive',
            '{"type":"after","data":{"status":"complete"}}'
        )
    )
    if (-not $IsWindows) {
        [IO.File]::SetUnixFileMode(
            $jsonlPath,
            [IO.UnixFileMode]::UserRead -bor
                [IO.UnixFileMode]::UserWrite -bor
                [IO.UnixFileMode]::GroupRead
        )
        $originalMode = [IO.File]::GetUnixFileMode($jsonlPath)
    }

    & $redactor $logDirectory 3>&1 | Out-Null
    $directoryRecords = @(
        [IO.File]::ReadAllLines($jsonlPath) |
            Where-Object { $_ } |
            ForEach-Object { $_ | ConvertFrom-Json -Depth 100 }
    )
    if (-not ($directoryRecords | Where-Object {
        $_.type -eq 'shepherd.redaction_warning' -and $_.data.line -eq 2
    })) {
        throw 'Directory-mode malformed input was not replaced.'
    }
    if ([IO.File]::ReadAllText($jsonlPath).Contains(
        'ghp_directory_secret_must_not_survive'
    )) {
        throw 'Directory-mode malformed input secret leaked.'
    }
    if (-not $IsWindows -and
        [IO.File]::GetUnixFileMode($jsonlPath) -ne $originalMode) {
        throw 'Directory-mode redaction changed file permissions.'
    }

    $invalidJson = Join-Path $logDirectory 'invalid.json'
    [IO.File]::WriteAllText($invalidJson, '{not-json ghp_document_secret}')
    $invalidBefore = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData(
            [IO.File]::ReadAllBytes($invalidJson)
        )
    )
    $failed = $false
    try {
        & $redactor $logDirectory 3>&1 | Out-Null
    } catch {
        $failed = $true
    }
    if (-not $failed) {
        throw 'Malformed standalone JSON did not fail closed.'
    }
    $invalidAfter = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData(
            [IO.File]::ReadAllBytes($invalidJson)
        )
    )
    if ($invalidAfter -ne $invalidBefore) {
        throw 'Malformed standalone JSON was modified.'
    }
    if (Get-ChildItem -LiteralPath $logDirectory -Filter '*.redact.*') {
        throw 'Redaction temporary files were not cleaned up.'
    }

    Write-Host 'PowerShell secret redaction contract tests passed.'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
