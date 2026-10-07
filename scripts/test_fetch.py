import urllib.request, json, ssl, http.cookiejar

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj), urllib.request.HTTPSHandler(context=ctx))

# Login
req_login = urllib.request.Request(
    'https://dev.pmii-marketing.com/api/method/login',
    data=json.dumps({'usr': 'jptan@profinsights.biz', 'pwd': 'pims@admin'}).encode('utf-8'),
    headers={'Content-Type': 'application/json'}
)
opener.open(req_login)

fields = [
    "name", "company", "latitude", "longitude", "location_accuracy",
    "picture", "sales_rep", "contact", "last_name", "position_or_role",
    "email_address", "contact_number", "date_and_time_of_sales_appointment",
    "decision_maker_or_responsible_person_not_available", "reason_for_unsuccessful_call",
    "unsuccessful_call", "creation", "modified"
]
fields_json = urllib.parse.quote(json.dumps(fields))

# Test Successful
try:
    r1 = opener.open(urllib.request.Request(
        f'https://dev.pmii-marketing.com/api/resource/Successful%20COREnergy%20Engagement?fields={fields_json}&limit_page_length=5000'
    ))
    d1 = json.loads(r1.read().decode('utf-8')).get('data', [])
    print('Successful count:', len(d1))
except urllib.error.HTTPError as e:
    print('Successful failed:', e.code, e.read().decode('utf-8')[:300])

# Test Unsuccessful
# Test fields=[*]
try:
    r_star = opener.open(urllib.request.Request(
        'https://dev.pmii-marketing.com/api/resource/Successful%20COREnergy%20Engagement?fields=["*"]&limit=100'
    ))
    print('Successful with fields=[*]:', r_star.status)
except urllib.error.HTTPError as e:
    print('Failed fields=[*]:', e.code, e.read().decode('utf-8')[:300])

