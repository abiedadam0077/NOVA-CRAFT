import urllib.request
req = urllib.request.Request("https://raw.githubusercontent.com/playit-cloud/playit-agent/master/packages/agent_cli/src/main.rs")
try:
    with urllib.request.urlopen(req) as response:
        print(response.read().decode())
except Exception as e:
    pass
