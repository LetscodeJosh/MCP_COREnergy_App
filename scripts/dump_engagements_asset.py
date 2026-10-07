import urllib.request, urllib.parse, json, ssl, http.cookiejar

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
BASE_URL = 'https://dev.pmii-marketing.com'
cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj), urllib.request.HTTPSHandler(context=ctx))
data = json.dumps({'usr': 'jptan@profinsights.biz', 'pwd': 'pims@admin'}).encode('utf-8')
opener.open(urllib.request.Request(f'{BASE_URL}/api/method/login', data=data, headers={'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0'}))

# 1. Fetch Successful
succ_fields = '["name","company","latitude","longitude","location_accuracy","picture","sales_rep","contact","last_name","position_or_role","email_address","contact_number","date_and_time_of_sales_appointment","decision_maker_or_responsible_person_not_available","reason_for_unsuccessful_call","creation","modified"]'
url1 = f'{BASE_URL}/api/resource/Successful%20COREnergy%20Engagement?fields={urllib.parse.quote(succ_fields)}&limit=5000'
r1 = json.loads(opener.open(urllib.request.Request(url1)).read().decode())
succ_list = r1.get('data', [])
for item in succ_list:
    item['unsuccessful_call'] = 0

# 2. Fetch Unsuccessful
unsucc_fields = '["name","company","latitude","longitude","location_accuracy","picture","sales_rep","contact","last_name","position_or_role","email_address","contact_number","date_and_time_of_sales_appointment","reason_for_unsuccessful_call","creation","modified"]'
url2 = f'{BASE_URL}/api/resource/Unsuccessful%20COREnergy%20Engagement?fields={urllib.parse.quote(unsucc_fields)}&limit=5000'
r2 = json.loads(opener.open(urllib.request.Request(url2)).read().decode())
unsucc_list = r2.get('data', [])
for item in unsucc_list:
    item['unsuccessful_call'] = 1

combined = succ_list + unsucc_list
with open('assets/engagements.json', 'w', encoding='utf-8') as f:
    json.dump(combined, f, indent=2)

print(f"Successfully saved {len(combined)} records to assets/engagements.json")
