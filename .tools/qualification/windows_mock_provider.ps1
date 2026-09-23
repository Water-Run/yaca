<#
Author: WaterRun
Date: 2026-09-23
File: windows_mock_provider.ps1
Description: Synthetic loopback provider for the Windows deployment smoke journey.
#>

# Synthetic loopback provider for the Windows deployment smoke journey.
# Run only in an isolated test directory; it does not contact a model service.
param([int]$Port = 18632, [string]$Root = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
$serial = 0
try {
    while ($serial -lt 10) {
        $context = $listener.GetContext()
        $reader = [System.IO.StreamReader]::new($context.Request.InputStream)
        $body = $reader.ReadToEnd()
        $reader.Dispose()
        $request = $body | ConvertFrom-Json
        $serial++
        [System.IO.File]::WriteAllText((Join-Path $Root "request-$serial.json"), $body)
        switch ($serial) {
            1 { $name='list'; $arguments=@{path="$Root/workspace"; depth=0; page_size=20} }
            2 { $name='write'; $arguments=@{path="$Root/workspace/hello.txt"; mode='create';
                    content="remote smoke`n"; encoding='utf-8'; newline_policy='lf'} }
            3 { $name='read'; $arguments=@{path="$Root/workspace/hello.txt"; start_line=1; max_lines=20} }
            4 { $name='exec'; $arguments=@{command='echo REMOTE-SHELL-OK'} }
            5 { $name='yaca_finish'; $arguments=@{summary='REMOTE-SMOKE-OK'} }
            default { $name='yaca_finish'; $arguments=@{summary='REMOTE-RESUME-OK'} }
        }
        $call = @{id="smoke-$serial"; type='function'; function=@{
            name=$name; arguments=($arguments | ConvertTo-Json -Compress)
        }}
        if ($request.stream) {
            $call.index=0
            $start=@{id="response-$serial"; choices=@(@{index=0;
                delta=@{role='assistant'; tool_calls=@($call)}; finish_reason=$null})}
            $end=@{id="response-$serial"; choices=@(@{index=0;
                delta=@{}; finish_reason='tool_calls'})}
            $text="data: $($start | ConvertTo-Json -Depth 20 -Compress)`n`n" +
                "data: $($end | ConvertTo-Json -Depth 20 -Compress)`n`ndata: [DONE]`n`n"
            $context.Response.ContentType='text/event-stream'
        } else {
            $response=@{id="response-$serial"; choices=@(@{index=0;
                message=@{role='assistant'; content=$null; tool_calls=@($call)};
                finish_reason='tool_calls'})}
            $text=$response | ConvertTo-Json -Depth 20 -Compress
            $context.Response.ContentType='application/json'
        }
        $bytes=[System.Text.Encoding]::UTF8.GetBytes($text)
        $context.Response.ContentLength64=$bytes.Length
        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $context.Response.Close()
    }
} finally {
    $listener.Stop()
    $listener.Close()
}
