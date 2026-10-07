import urllib.request
import urllib.parse
import json
import ssl
import http.cookiejar
import re

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

BASE_URL = 'https://dev.pmii-marketing.com'
cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj), urllib.request.HTTPSHandler(context=ctx))

login_data = json.dumps({'usr': 'jptan@profinsights.biz', 'pwd': 'pims@admin'}).encode('utf-8')
opener.open(urllib.request.Request(f'{BASE_URL}/api/method/login', data=login_data, headers={'Content-Type': 'application/json'}))

q = urllib.parse.urlencode({
    'fields': json.dumps(["name", "institution_name"]),
    'filters': json.dumps([["institution_name", "like", "%Bank Of Makati%"]])
})
res = opener.open(urllib.request.Request(f'{BASE_URL}/api/resource/Institution?{q}'))
print('Bank Of Makati in Institution:', json.loads(res.read().decode('utf-8'))['data'])

# Extract CSRF
app_res = opener.open(urllib.request.Request(f'{BASE_URL}/app'))
csrf_match = re.search(r'frappe\.csrf_token\s*=\s*["\x27]([^"\x27]+)["\x27]', app_res.read().decode('utf-8'))
csrf = csrf_match.group(1) if csrf_match else ''

# Test 1: with company = INST-00012
p1 = {
    'company': 'INST-00012',
    'sales_rep': 'jptan@profinsights.biz',
    'date_and_time_of_sales_appointment': '2026-10-01 12:35:00',
    'latitude': '14.5995',
    'longitude': '120.9842',
    'contact': 'Dr. Test'
}
req1 = urllib.request.Request(f'{BASE_URL}/api/resource/Successful%20COREnergy%20Engagement', data=json.dumps(p1).encode('utf-8'), headers={'Content-Type':'application/json','X-Frappe-CSRF-Token':csrf}, method='POST')
try:
    res1 = opener.open(req1)
    name1 = json.loads(res1.read().decode('utf-8'))['data']['name']
    print(f"POST with INST-00012: 200 OK -> created {name1}")
except urllib.error.HTTPError as e:
    print(f"POST with INST-00012 failed: {e.code} - {e.read().decode('utf-8')[:200]}")

# Test 2: without company
p2 = {
    'sales_rep': 'jptan@profinsights.biz',
    'date_and_time_of_sales_appointment': '2026-10-01 12:35:00',
    'latitude': '14.5995',
    'longitude': '120.9842',
    'contact': 'Dr. Test'
}
req2 = urllib.request.Request(f'{BASE_URL}/api/resource/Successful%20COREnergy%20Engagement', data=json.dumps(p2).encode('utf-8'), headers={'Content-Type':'application/json','X-Frappe-CSRF-Token':csrf}, method='POST')
try:
    res2 = opener.open(req2)
    name2 = json.loads(res2.read().decode('utf-8'))['data']['name']
    print(f"POST without company: 200 OK -> created {name2}")
except urllib.error.HTTPError as e:
    print(f"POST without company failed: {e.code} - {e.read().decode('utf-8')[:200]}")
