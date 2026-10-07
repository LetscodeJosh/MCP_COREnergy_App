"""
End-to-end test simulating the exact tablet MCP App flow:
1. Login -> extract sid
2. Fetch CSRF token
3. GET Successful COREnergy Engagement
4. GET Unsuccessful COREnergy Engagement
5. GET Institution
6. GET COREnergy Engage Copy
7. Test POST create engagement with sanitized payload
"""
import urllib.request, json, ssl, http.cookiejar, re

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

BASE_URL = 'https://dev.pmii-marketing.com'
cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(
    urllib.request.HTTPCookieProcessor(cj),
    urllib.request.HTTPSHandler(context=ctx)
)

print("=" * 60)
print("STEP 1: Login")
print("=" * 60)
login_data = json.dumps({'usr': 'jptan@profinsights.biz', 'pwd': 'pims@admin'}).encode('utf-8')
login_req = urllib.request.Request(
    f'{BASE_URL}/api/method/login',
    data=login_data,
    headers={'Content-Type': 'application/json', 'Accept': 'application/json'}
)
login_res = opener.open(login_req)
login_body = json.loads(login_res.read().decode('utf-8'))
print(f"  Login status: {login_res.status}")
print(f"  Login body message: {login_body.get('message')}")

# Show cookies
for cookie in cj:
    print(f"  Cookie: {cookie.name}={cookie.value[:20]}...")

# Simulate Dart's raw cookie header parsing issue
# In Dart http, set-cookie is concatenated. Let's see what headers look like
raw_headers = dict(login_res.headers)
set_cookie = raw_headers.get('Set-Cookie', raw_headers.get('set-cookie', ''))
print(f"\n  Raw Set-Cookie header (first 200 chars): {str(set_cookie)[:200]}")

# Test regex extraction
sid_match = re.search(r'sid=([^;,\s]+)', str(set_cookie))
if sid_match:
    print(f"  Regex sid extraction: sid={sid_match.group(1)[:20]}...")
else:
    print(f"  WARNING: Could not extract sid with regex!")

print()
print("=" * 60)
print("STEP 2: Get CSRF Token")
print("=" * 60)
app_res = opener.open(urllib.request.Request(f'{BASE_URL}/app'))
html = app_res.read().decode('utf-8')
csrf_match = re.search(r'frappe\.csrf_token\s*=\s*["\'](.*?)["\']', html)
csrf = csrf_match.group(1) if csrf_match else None
print(f"  CSRF Token: {csrf[:20] if csrf else 'MISSING'}...")

print()
print("=" * 60)
print("STEP 3: Fetch Successful COREnergy Engagement")
print("=" * 60)
fields = '["name","company","latitude","longitude","location_accuracy","picture","sales_rep","contact","last_name","position_or_role","email_address","contact_number","date_and_time_of_sales_appointment","decision_maker_or_responsible_person_not_available","reason_for_unsuccessful_call","unsuccessful_call","creation","modified"]'
try:
    url = f'{BASE_URL}/api/resource/Successful%20COREnergy%20Engagement?fields={urllib.parse.quote(fields)}&limit_page_length=5000'
    r = opener.open(urllib.request.Request(url))
    data = json.loads(r.read().decode('utf-8')).get('data', [])
    print(f"  Status: {r.status}")
    print(f"  Count: {len(data)}")
    if data:
        print(f"  First record keys: {list(data[0].keys())}")
        print(f"  First record company: {data[0].get('company')}")
        print(f"  First record name: {data[0].get('name')}")
except urllib.error.HTTPError as e:
    print(f"  FAILED: {e.code} {e.read().decode('utf-8')[:300]}")

print()
print("=" * 60)
print("STEP 4: Fetch Unsuccessful COREnergy Engagement")
print("=" * 60)
try:
    url = f'{BASE_URL}/api/resource/Unsuccessful%20COREnergy%20Engagement?fields={urllib.parse.quote(fields)}&limit_page_length=5000'
    r = opener.open(urllib.request.Request(url))
    data = json.loads(r.read().decode('utf-8')).get('data', [])
    print(f"  Status: {r.status}")
    print(f"  Count: {len(data)}")
    if data:
        print(f"  First record keys: {list(data[0].keys())}")
except urllib.error.HTTPError as e:
    print(f"  FAILED: {e.code} {e.read().decode('utf-8')[:300]}")

print()
print("=" * 60)
print("STEP 5: Fetch Institution")
print("=" * 60)
try:
    inst_fields = '["name","institution_name","region_name","province_name","city_municipality","street_address"]'
    url = f'{BASE_URL}/api/resource/Institution?fields={urllib.parse.quote(inst_fields)}&limit_page_length=5000'
    r = opener.open(urllib.request.Request(url))
    data = json.loads(r.read().decode('utf-8')).get('data', [])
    print(f"  Status: {r.status}")
    print(f"  Count: {len(data)}")
except urllib.error.HTTPError as e:
    print(f"  FAILED: {e.code} {e.read().decode('utf-8')[:300]}")

print()
print("=" * 60)
print("STEP 6: Fetch COREnergy Engage Copy")
print("=" * 60)
try:
    ce_fields = '["name","institution_name","region_name","province_name","city_municipality","barangay_name","street_address","sales_rep","leads_source","leads_status","ownership_nationality","creation","modified"]'
    url = f'{BASE_URL}/api/resource/COREnergy%20Engage%20Copy?fields={urllib.parse.quote(ce_fields)}&limit_page_length=5000'
    r = opener.open(urllib.request.Request(url))
    data = json.loads(r.read().decode('utf-8')).get('data', [])
    print(f"  Status: {r.status}")
    print(f"  Count: {len(data)}")
except urllib.error.HTTPError as e:
    print(f"  FAILED: {e.code} {e.read().decode('utf-8')[:300]}")

print()
print("=" * 60)
print("STEP 7: Test POST Create Successful Engagement (sanitized)")
print("=" * 60)
headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'X-Frappe-CSRF-Token': csrf or ''
}
test_payload = {
    "latitude": "14.5995",
    "longitude": "120.9842",
    "sales_rep": "jptan@profinsights.biz",
    "contact": "TestDoctor",
    "last_name": "AutoTest",
    "position_or_role": "Pediatrician",
    "date_and_time_of_sales_appointment": "2026-10-01 10:00:00"
    # NOTE: No 'company' field - this is the fix
}
try:
    req = urllib.request.Request(
        f'{BASE_URL}/api/resource/Successful%20COREnergy%20Engagement',
        data=json.dumps(test_payload).encode('utf-8'),
        headers=headers
    )
    resp = opener.open(req)
    result = json.loads(resp.read().decode('utf-8'))
    print(f"  Status: {resp.status}")
    print(f"  Created name: {result.get('data', {}).get('name')}")
    print(f"  SUCCESS!")
except urllib.error.HTTPError as e:
    body = e.read().decode('utf-8')[:500]
    print(f"  FAILED: {e.code}")
    print(f"  Body: {body}")

print()
print("=" * 60)
print("STEP 8: Test POST with company='COREnergy' (should 417)")
print("=" * 60)
test_payload_bad = {
    "company": "COREnergy",
    "latitude": "14.5995",
    "longitude": "120.9842",
    "sales_rep": "jptan@profinsights.biz",
    "contact": "TestBad",
    "last_name": "ShouldFail",
    "date_and_time_of_sales_appointment": "2026-10-01 10:00:00"
}
try:
    req2 = urllib.request.Request(
        f'{BASE_URL}/api/resource/Successful%20COREnergy%20Engagement',
        data=json.dumps(test_payload_bad).encode('utf-8'),
        headers=headers
    )
    resp2 = opener.open(req2)
    print(f"  Status: {resp2.status} (unexpected success)")
except urllib.error.HTTPError as e:
    body = e.read().decode('utf-8')[:500]
    print(f"  Status: {e.code} (expected 417)")
    print(f"  Body: {body[:200]}")

print()
print("=" * 60)
print("STEP 9: Ping test (checkOnlineStatus)")
print("=" * 60)
try:
    ping_res = opener.open(urllib.request.Request(f'{BASE_URL}/api/method/ping'))
    print(f"  Ping status: {ping_res.status}")
    print(f"  Ping body: {ping_res.read().decode('utf-8')[:100]}")
except Exception as e:
    print(f"  Ping FAILED: {e}")

print()
print("=" * 60)
print("ALL TESTS COMPLETE")
print("=" * 60)
