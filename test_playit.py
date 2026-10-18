import urllib.request, json
req = urllib.request.Request("https://api.playit.gg/v1/agents/routing/create_guest", headers={"Content-Type": "application/json"}, data=b"{}", method="POST")
try:
    with urllib.request.urlopen(req) as response:
        print("CREATE:", response.read().decode())
except Exception as e:
    print("CREATE ERR:", e)
    try:
        print("ERR BODY:", e.read().decode())
    except: pass
