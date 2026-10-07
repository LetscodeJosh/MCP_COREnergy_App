import http.server
import socketserver
import os
import socket

PORT = 8080
REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RELEASES_DIR = os.path.join(REPO_DIR, "releases")

def get_local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('8.8.8.8', 1))
        IP = s.getsockname()[0]
    except Exception:
        IP = '127.0.0.1'
    finally:
        s.close()
    return IP

LOCAL_IP = get_local_ip()

HTML_TEMPLATE = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PIMS MCP Tablet Deployment Portal</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #f0f4f8;
            color: #1e293b;
            margin: 0;
            padding: 20px;
        }}
        .card {{
            max-width: 520px;
            margin: 20px auto;
            background: white;
            border-radius: 16px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.08);
            padding: 28px;
        }}
        .badge {{
            display: inline-block;
            background: #2563eb;
            color: white;
            font-size: 12px;
            font-weight: 700;
            padding: 4px 10px;
            border-radius: 20px;
            text-transform: uppercase;
        }}
        h1 {{
            font-size: 22px;
            margin: 14px 0 6px 0;
            color: #0f172a;
        }}
        .subtitle {{
            font-size: 14px;
            color: #64748b;
            margin-bottom: 24px;
        }}
        .alert {{
            background: #fef2f2;
            border-left: 4px solid #ef4444;
            padding: 14px;
            border-radius: 8px;
            font-size: 13px;
            color: #991b1b;
            margin-bottom: 24px;
            line-height: 1.5;
        }}
        .btn {{
            display: block;
            width: 100%;
            box-sizing: border-box;
            background: #2563eb;
            color: white;
            text-align: center;
            padding: 16px;
            border-radius: 12px;
            text-decoration: none;
            font-size: 16px;
            font-weight: 700;
            margin-bottom: 12px;
            box-shadow: 0 4px 12px rgba(37,99,235,0.25);
        }}
        .btn:active {{
            background: #1d4ed8;
        }}
        .btn-secondary {{
            background: #f8fafc;
            color: #334155;
            border: 1px solid #cbd5e1;
            box-shadow: none;
        }}
        .steps {{
            margin-top: 24px;
            background: #f8fafc;
            padding: 18px;
            border-radius: 12px;
            font-size: 13px;
            color: #475569;
        }}
        .steps ol {{
            margin: 8px 0 0 0;
            padding-left: 20px;
        }}
        .steps li {{
            margin-bottom: 8px;
        }}
    </style>
</head>
<body>
    <div class="card">
        <span class="badge">Version 0.2.4 (High-Accuracy GPS & Live Coverage Map)</span>
        <h1>Install MCP COREnergy on Tablet</h1>
        <div class="subtitle">Direct tablet installation for Samsung Galaxy Tab A8</div>

        <div class="alert">
            <strong>CRITICAL STEP BEFORE INSTALLING:</strong><br>
            You <strong>MUST UNINSTALL</strong> any previous "PIMS MCP" or "PIMS HCP" app currently installed on this tablet. Otherwise, Android will block the update due to keystore signature conflicts, and you will remain on the old version!
        </div>

        <a href="/download/PIMS_MCP_COREnergy_Release.apk" class="btn">
            ⬇️ Download PIMS MCP (COREnergy) APK
        </a>

        <div class="steps">
            <strong>Quick 3-Step Installation:</strong>
            <ol>
                <li>Long-press the old PIMS/MCP app icon on your tablet screen and tap <strong>Uninstall</strong>.</li>
                <li>Tap the blue download button above.</li>
                <li>Open the downloaded file and tap <strong>Install</strong>.</li>
            </ol>
        </div>
    </div>
</body>
</html>
"""

class TabletDeploymentHandler(http.server.SimpleHTTPRequestHandler):
    def do_HEAD(self):
        if self.path == "/" or self.path == "/index.html":
            self.send_response(200)
            self.send_header("Content-type", "text/html; charset=utf-8")
            self.end_headers()
        elif self.path.startswith("/download/"):
            filename = self.path.replace("/download/", "")
            filepath = os.path.join(RELEASES_DIR, filename)
            if os.path.exists(filepath):
                self.send_response(200)
                self.send_header("Content-type", "application/vnd.android.package-archive")
                self.send_header("Content-Disposition", f"attachment; filename={filename}")
                self.send_header("Content-Length", str(os.path.getsize(filepath)))
                self.end_headers()
            else:
                self.send_error(404, "File not found")
        else:
            super().do_HEAD()

    def do_GET(self):
        if self.path == "/" or self.path == "/index.html":
            self.send_response(200)
            self.send_header("Content-type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(HTML_TEMPLATE.encode("utf-8"))
        elif self.path.startswith("/download/"):
            filename = self.path.replace("/download/", "")
            filepath = os.path.join(RELEASES_DIR, filename)
            if os.path.exists(filepath):
                self.send_response(200)
                self.send_header("Content-type", "application/vnd.android.package-archive")
                self.send_header("Content-Disposition", f"attachment; filename={filename}")
                self.send_header("Content-Length", str(os.path.getsize(filepath)))
                self.end_headers()
                with open(filepath, "rb") as f:
                    while chunk := f.read(65536):
                        self.wfile.write(chunk)
            else:
                self.send_error(404, "File not found")
        else:
            super().do_GET()

if __name__ == "__main__":
    os.chdir(REPO_DIR)
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), TabletDeploymentHandler) as httpd:
        print(f"============================================================")
        print(f"  Tablet Deployment Server is LIVE!")
        print(f"  Open this URL on your Samsung Galaxy A8 Tablet:")
        print(f"  --> http://{LOCAL_IP}:{PORT}")
        print(f"============================================================")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down server...")
