import urllib.request
import urllib.parse
import json
import ssl
import http.cookiejar

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

BASE_URL = 'https://dev.pmii-marketing.com'
cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj), urllib.request.HTTPSHandler(context=ctx))

login_data = json.dumps({'usr': 'jptan@profinsights.biz', 'pwd': 'pims@admin'}).encode('utf-8')
login_req = urllib.request.Request(f'{BASE_URL}/api/method/login', data=login_data, headers={'Content-Type': 'application/json'})
res = opener.open(login_req)
print(f"Login status: {res.status}")

# Check Successful COREnergy Engagement
req1 = urllib.request.Request(f'{BASE_URL}/api/resource/Successful%20COREnergy%20Engagement?fields=["name","company","latitude","longitude","sales_rep","creation"]&limit=5')
body1 = json.loads(opener.open(req1).read().decode('utf-8'))
print("\n--- Successful COREnergy Engagement (5 samples) ---")
print(json.dumps(body1.get('data', []), indent=2))

# Check Unsuccessful COREnergy Engagement
req1b = urllib.request.Request(f'{BASE_URL}/api/resource/Unsuccessful%20COREnergy%20Engagement?fields=["name","company","latitude","longitude","sales_rep","reason_for_unsuccessful_call","creation"]&limit=5')
body1b = json.loads(opener.open(req1b).read().decode('utf-8'))
print("\n--- Unsuccessful COREnergy Engagement (5 samples) ---")
print(json.dumps(body1b.get('data', []), indent=2))

# Check COREnergy Engage Copy
req2 = urllib.request.Request(f'{BASE_URL}/api/resource/COREnergy%20Engage%20Copy?fields=["name","institution_name","latitude","longitude","sales_rep","creation"]&limit=5')
body2 = json.loads(opener.open(req2).read().decode('utf-8'))
print("\n--- COREnergy Engage Copy (5 samples) ---")
print(json.dumps(body2.get('data', []), indent=2))

# Test updating a sample COREnergy Engage Copy with visits
import re
app_res = opener.open(urllib.request.Request(f'{BASE_URL}/app'))
html = app_res.read().decode('utf-8')
csrf_match = re.search(r'frappe\.csrf_token\s*=\s*["\x27]([^"\x27]+)["\x27]', html)
csrf = csrf_match.group(1) if csrf_match else ''
print(f"Extracted CSRF token: {csrf[:10]}...")

# Test 1: Update COREnergy Engage Copy with visits child table
payload1 = {
    'visits': [
        {
            'visit_date': '2026-10-01',
            'person_engaged': 'Dr. Test',
            'successful_call': 1,
            'unsuccessful_call': 0,
            'notes': 'Test call via script'
        }
    ]
}
try:
    req = urllib.request.Request(
        f'{BASE_URL}/api/resource/COREnergy%20Engage%20Copy/INST-03995',
        data=json.dumps(payload1).encode('utf-8'),
        headers={'Content-Type': 'application/json', 'X-Frappe-CSRF-Token': csrf},
        method='PUT'
    )
    res = opener.open(req)
    print(f"PUT COREnergy Engage Copy/INST-03995: {res.status} OK")
except urllib.error.HTTPError as e:
    print(f"PUT COREnergy Engage Copy failed: {e.code} - {e.read().decode('utf-8', errors='ignore')[:300]}")

# Test 2: Create Successful COREnergy Engagement
payload2 = {
    'company': 'INST-03995',
    'sales_rep': 'jptan@profinsights.biz',
    'date_and_time_of_sales_appointment': '2026-10-01 12:35:00',
    'latitude': '14.5995',
    'longitude': '120.9842',
    'contact': 'Dr. Test'
}
try:
    req = urllib.request.Request(
        f'{BASE_URL}/api/resource/Successful%20COREnergy%20Engagement',
        data=json.dumps(payload2).encode('utf-8'),
        headers={'Content-Type': 'application/json', 'X-Frappe-CSRF-Token': csrf},
        method='POST'
    )
    res = opener.open(req)
    data = json.loads(res.read().decode('utf-8')).get('data', {})
    print(f"POST Successful COREnergy Engagement: {res.status} OK -> created {data.get('name')}")
except urllib.error.HTTPError as e:
    print(f"POST Successful COREnergy Engagement failed: {e.code} - {e.read().decode('utf-8', errors='ignore')[:300]}")
    cnt_url = f'{BASE_URL}/api/method/frappe.client.get_count?doctype={urllib.parse.quote(dt)}'
    try:
        cnt_res = opener.open(urllib.request.Request(cnt_url))
        cnt = json.loads(cnt_res.read().decode('utf-8')).get('message', 0)
        print(f"Count of {dt}: {cnt}")
    except Exception as e:
        print(f"Count of {dt}: error {e}")
