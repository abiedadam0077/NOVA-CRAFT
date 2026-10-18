import urllib.request, json, secrets
code = secrets.token_hex(5)
urllib.request.urlopen(urllib.request.Request("https://api.playit.gg/claim/setup", headers={"Content-Type": "application/json"}, data=json.dumps({"code": code, "agent_type": "self-managed", "version": "playit-cli 1.0.10"}).encode("utf-8"), method="POST"))
req = urllib.request.Request("https://api.playit.gg/claim/exchange", headers={"Content-Type": "application/json"}, data=json.dumps({"code": code}).encode("utf-8"), method="POST")
try:
    with urllib.request.urlopen(req) as response:
        print("EXCHANGE:", response.read().decode())
except Exception as e:
    print("EXCHANGE ERR:", e)
    try:
        print("ERR BODY:", e.read().decode())
    except: pass
