import urllib.request, json, ssl, http.cookiejar

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
BASE_URL = 'https://dev.pmii-marketing.com'
cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj), urllib.request.HTTPSHandler(context=ctx))
data = json.dumps({'usr': 'jptan@profinsights.biz', 'pwd': 'pims@admin'}).encode('utf-8')
opener.open(urllib.request.Request(f'{BASE_URL}/api/method/login', data=data, headers={'Content-Type': 'application/json'}))

res = opener.open(urllib.request.Request(f'{BASE_URL}/api/resource/Successful%20COREnergy%20Engagement?limit=5'))
data = json.loads(res.read().decode('utf-8')).get('data', [])
for r in data:
    name = r['name']
    dres = opener.open(urllib.request.Request(f'{BASE_URL}/api/resource/Successful%20COREnergy%20Engagement/{urllib.parse.quote(name)}'))
    doc = json.loads(dres.read().decode('utf-8')).get('data', {})
    print(name, '-> company:', doc.get('company'), '| sales_rep:', doc.get('sales_rep'))

print("\nChecking Unsuccessful COREnergy Engagement:")
res2 = opener.open(urllib.request.Request(f'{BASE_URL}/api/resource/Unsuccessful%20COREnergy%20Engagement?limit=5'))
data2 = json.loads(res2.read().decode('utf-8')).get('data', [])
for r in data2:
    name = r['name']
    dres = opener.open(urllib.request.Request(f'{BASE_URL}/api/resource/Unsuccessful%20COREnergy%20Engagement/{urllib.parse.quote(name)}'))
    doc = json.loads(dres.read().decode('utf-8')).get('data', {})
    print(name, '-> company:', doc.get('company'), '| reason:', doc.get('reason_for_unsuccessful_call'))
