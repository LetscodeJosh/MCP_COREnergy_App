import urllib.request, urllib.parse, json, ssl, http.cookiejar

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
BASE_URL = 'https://dev.pmii-marketing.com'
cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj), urllib.request.HTTPSHandler(context=ctx))
data = json.dumps({'usr': 'jptan@profinsights.biz', 'pwd': 'pims@admin'}).encode('utf-8')
opener.open(urllib.request.Request(f'{BASE_URL}/api/method/login', data=data, headers={'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0'}))

inst_fields = '["name","institution_name","region_name","province_name","city_municipality","street_address"]'
url = f'{BASE_URL}/api/resource/Institution?fields={urllib.parse.quote(inst_fields)}&limit=5000'
r = json.loads(opener.open(urllib.request.Request(url)).read().decode())
inst_list = r.get('data', [])

with open('assets/institutions.json', 'w', encoding='utf-8') as f:
    json.dump(inst_list, f, indent=2)

print(f"Successfully saved {len(inst_list)} institutions into assets/institutions.json")
