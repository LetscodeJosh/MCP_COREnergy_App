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

# Test 1: Successful COREnergy Engagement
fields_list = [
    "name", "company", "latitude", "longitude", "location_accuracy", "picture",
    "sales_rep", "contact", "last_name", "position_or_role", "email_address",
    "contact_number", "date_and_time_of_sales_appointment",
    "decision_maker_or_responsible_person_not_available",
    "reason_for_unsuccessful_call", "unsuccessful_call", "creation", "modified"
]
fields_json = json.dumps(fields_list)

for dt in [
    'Successful COREnergy Engagement',
    'Unsuccessful COREnergy Engagement',
    'COREnergy Engage Copy',
    'COREnergy Engage',
    'Institution'
]:
    enc_dt = urllib.parse.quote(dt)
    url = f"{BASE_URL}/api/resource/{enc_dt}?limit=5"
    if 'Engagement' in dt:
        url += f"&fields={urllib.parse.quote(fields_json)}"
    elif dt in ['COREnergy Engage Copy', 'COREnergy Engage']:
        copy_fields = json.dumps(["name", "institution_name", "region_name", "province_name", "city_municipality", "barangay_name", "street_address", "sales_rep", "leads_source", "leads_status", "ownership_nationality", "creation", "modified"])
        url += f"&fields={urllib.parse.quote(copy_fields)}"
    elif dt == 'Institution':
        inst_fields = json.dumps(["name", "institution_name", "region_name", "province_name", "city_municipality", "street_address"])
        url += f"&fields={urllib.parse.quote(inst_fields)}"

    try:
        req = urllib.request.Request(url)
        resp = opener.open(req)
        body = json.loads(resp.read().decode('utf-8'))
        count = len(body.get('data', []))
        print(f"SUCCESS: {dt} -> 200 OK (returned {count} records)")
    except urllib.error.HTTPError as e:
        err_msg = e.read().decode('utf-8', errors='ignore')
        print(f"FAILED: {dt} -> HTTP {e.code}: {err_msg[:400]}")
    except Exception as e:
        print(f"ERROR: {dt} -> {e}")
