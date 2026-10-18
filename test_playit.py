import urllib.request, json
req = urllib.request.Request(
    "https://api.playit.gg/claim/setup",
    headers={"Content-Type": "application/json"},
    data=json.dumps({"code": "12345678", "agent_type": "self-managed", "version": "playit-cli 1.0.10"}).encode("utf-8"),
    method="POST"
)
try:
    with urllib.request.urlopen(req) as response:
        print("CREATE:", response.read().decode())
except Exception as e:
    print("CREATE ERR:", e)
    try:
        print("ERR BODY:", e.read().decode())
    except: pass
