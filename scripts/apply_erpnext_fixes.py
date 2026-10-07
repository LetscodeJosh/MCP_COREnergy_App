import urllib.request, urllib.parse, json, ssl, http.cookiejar

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
BASE_URL = 'https://dev.pmii-marketing.com'
cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj), urllib.request.HTTPSHandler(context=ctx))
data = json.dumps({'usr': 'jptan@profinsights.biz', 'pwd': 'pims@admin'}).encode('utf-8')
opener.open(urllib.request.Request(f'{BASE_URL}/api/method/login', data=data, headers={'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0'}))

# 1. Add Custom DocPerm for COREnergy Engage Copy for 'Employee - COREnergy'
docperm_payloads = [
    {
        "parent": "COREnergy Engage Copy",
        "parenttype": "DocType",
        "parentfield": "permissions",
        "role": "Employee - COREnergy",
        "permlevel": 0,
        "read": 1,
        "write": 1,
        "create": 1,
        "delete": 0,
        "select": 1,
        "report": 1,
        "export": 1,
        "share": 1
    },
    {
        "parent": "COREnergy Engage Copy",
        "parenttype": "DocType",
        "parentfield": "permissions",
        "role": "Next Level Manager - COREnergy",
        "permlevel": 0,
        "read": 1,
        "write": 1,
        "create": 1,
        "delete": 0,
        "select": 1,
        "report": 1,
        "export": 1,
        "share": 1
    }
]

for p in docperm_payloads:
    try:
        url = f'{BASE_URL}/api/resource/Custom%20DocPerm'
        req = urllib.request.Request(url, data=json.dumps(p).encode('utf-8'), headers={'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0'})
        res = json.loads(opener.open(req).read().decode('utf-8'))
        print(f"Added Custom DocPerm for {p['role']} on {p['parent']}: {res.get('data', {}).get('name')}")
    except Exception as e:
        print(f"Error adding Custom DocPerm for {p['role']}: {e}")
        if hasattr(e, 'read'):
            print(e.read().decode('utf-8')[:300])

# 2. Add Custom Field 'ownership_nationality' to 'COREnergy Engage'
cf_payload = {
    "dt": "COREnergy Engage",
    "fieldname": "ownership_nationality",
    "label": "Ownership Nationality",
    "fieldtype": "Select",
    "options": "Filipino\nForeign\nJoint Venture",
    "insert_after": "leads_status"
}

try:
    url = f'{BASE_URL}/api/resource/Custom%20Field'
    req = urllib.request.Request(url, data=json.dumps(cf_payload).encode('utf-8'), headers={'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0'})
    res = json.loads(opener.open(req).read().decode('utf-8'))
    print(f"Added Custom Field ownership_nationality on COREnergy Engage: {res.get('data', {}).get('name')}")
except Exception as e:
    print(f"Error adding Custom Field on COREnergy Engage: {e}")
    if hasattr(e, 'read'):
        print(e.read().decode('utf-8')[:300])
