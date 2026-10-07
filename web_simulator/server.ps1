# Lightweight PowerShell TCP Web Server for local network PWA testing
$port = 8080
$address = [System.Net.IPAddress]::Any
$server = New-Object System.Net.Sockets.TcpListener($address, $port)

try {
    $server.Start()
    Write-Host "TCP Web Server started successfully!"
    Write-Host "👉 Local Access: http://localhost:$port"
    Write-Host "👉 Sharable Mobile Link: http://192.168.2.175:$port"
} catch {
    Write-Error ("Failed to start server on port $port. Error: " + $_)
    exit
}

# Keep track of server running state
$running = $true

# Trap Ctrl+C to clean up socket on exit
trap {
    Write-Host "`nStopping server..."
    $server.Stop()
    exit
}

while ($running) {
    if ($server.Pending()) {
        $client = $server.AcceptTcpClient()
        $stream = $client.GetStream()
        $reader = New-Object System.IO.StreamReader($stream)
        
        # Read the request line
        $requestLine = $reader.ReadLine()
        if ($requestLine) {
            $parts = $requestLine -split ' '
            if ($parts.Length -ge 2) {
                $urlPath = $parts[1]
                
                # Strip query parameters if any (e.g. ?v=1)
                $urlPath = $urlPath.Split('?')[0]
                
                if ($urlPath -eq "/" -or $urlPath -eq "") {
                    $urlPath = "/index.html"
                }
                
                # Sanitize path to prevent folder traversal
                $sanitizedPath = $urlPath.Replace("..", "").TrimStart('/')
                $filePath = Join-Path $PSScriptRoot $sanitizedPath
                
                if (Test-Path $filePath -PathType Leaf) {
                    $bytes = [System.IO.File]::ReadAllBytes($filePath)
                    $contentType = "application/octet-stream"
                    
                    if ($filePath.EndsWith(".html")) { $contentType = "text/html; charset=utf-8" }
                    elseif ($filePath.EndsWith(".css")) { $contentType = "text/css; charset=utf-8" }
                    elseif ($filePath.EndsWith(".js")) { $contentType = "application/javascript; charset=utf-8" }
                    elseif ($filePath.EndsWith(".json")) { $contentType = "application/json; charset=utf-8" }
                    elseif ($filePath.EndsWith(".png")) { $contentType = "image/png" }
                    elseif ($filePath.EndsWith(".jpg") -or $filePath.EndsWith(".jpeg")) { $contentType = "image/jpeg" }
                    elseif ($filePath.EndsWith(".svg")) { $contentType = "image/svg+xml" }
                    
                    $headers = "HTTP/1.1 200 OK`r`n" +
                               "Content-Type: $contentType`r`n" +
                               "Content-Length: $($bytes.Length)`r`n" +
                               "Access-Control-Allow-Origin: *`r`n" +
                               "Connection: close`r`n`r`n"
                               
                    $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($headers)
                    $stream.Write($headerBytes, 0, $headerBytes.Length)
                    $stream.Write($bytes, 0, $bytes.Length)
                } else {
                    $html = "404 Not Found"
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
                    $headers = "HTTP/1.1 404 Not Found`r`n" +
                               "Content-Type: text/plain`r`n" +
                               "Content-Length: $($bytes.Length)`r`n" +
                               "Connection: close`r`n`r`n"
                               
                    $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($headers)
                    $stream.Write($headerBytes, 0, $headerBytes.Length)
                    $stream.Write($bytes, 0, $bytes.Length)
                }
            }
        }
        $stream.Close()
        $client.Close()
    } else {
        Start-Sleep -Milliseconds 50
    }
}
