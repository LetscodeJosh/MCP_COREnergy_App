import urllib.request, json, ssl, http.cookiejar, re

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

BASE_URL = 'https://dev.pmii-marketing.com'
cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj), urllib.request.HTTPSHandler(context=ctx))

# 1. Login
data = json.dumps({'usr': 'jptan@profinsights.biz', 'pwd': 'pims@admin'}).encode('utf-8')
login_res = opener.open(urllib.request.Request(f'{BASE_URL}/api/method/login', data=data, headers={'Content-Type': 'application/json'}))

# 2. Get CSRF Token
app_resp = opener.open(urllib.request.Request(f'{BASE_URL}/app'))
html = app_resp.read().decode('utf-8')
csrf = re.search(r'frappe\.csrf_token\s*=\s*["\x27]([^"\x27]+)["\x27]', html).group(1)

headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'X-Frappe-CSRF-Token': csrf
}

# 3. Test creating a visit with company = None
test_succ = {
    "latitude": "14.5995",
    "longitude": "120.9842",
    "sales_rep": "jptan@profinsights.biz",
    "contact": "Test Dr. Juan",
    "last_name": "Santos",
    "position_or_role": "Pediatrician",
    "date_and_time_of_sales_appointment": "2026-10-01 10:00:00"
}

req = urllib.request.Request(
    f'{BASE_URL}/api/resource/Successful%20COREnergy%20Engagement',
    data=json.dumps(test_succ).encode('utf-8'),
    headers=headers
)
try:
    resp = opener.open(req)
    created = json.loads(resp.read().decode('utf-8'))
    print('SUCCESS: Created Successful Engagement:', created.get('data', {}).get('name'))
except urllib.error.HTTPError as e:
    print('Failed with None:', e.code, e.read().decode('utf-8')[:300])

# 4. Test creating Unsuccessful engagement with company = "INST-02950"
test_unsucc = {
    "company": "INST-02950",
    "latitude": "14.5995",
    "longitude": "120.9842",
    "sales_rep": "jptan@profinsights.biz",
    "contact": "Test Contact",
    "last_name": "Cruz",
    "position_or_role": "Doctor",
    "reason_for_unsuccessful_call": "Prior appointment or letter needed",
    "date_and_time_of_sales_appointment": "2026-10-01 10:00:00"
}
req2 = urllib.request.Request(
    f'{BASE_URL}/api/resource/Unsuccessful%20COREnergy%20Engagement',
    data=json.dumps(test_unsucc).encode('utf-8'),
    headers=headers
)
try:
    resp2 = opener.open(req2)
    created2 = json.loads(resp2.read().decode('utf-8'))
    print('SUCCESS: Created Unsuccessful Engagement with institution ID:', created2.get('data', {}).get('name'))
except urllib.error.HTTPError as e:
    print('Failed with INST-02950:', e.code, e.read().decode('utf-8')[:300])
