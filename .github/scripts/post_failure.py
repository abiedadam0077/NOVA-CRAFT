import json
import os
import urllib.request

tail = ""
try:
    tail = open("/tmp/fail.txt", errors="ignore").read()[-55000:]
except OSError:
    tail = "(no build log captured)"
body = "CI failure log tail:\n\n```text\n" + tail + "\n```"
data = json.dumps({"body": body}).encode()
url = "https://api.github.com/repos/{}/commits/{}/comments".format(
    os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_SHA"]
)
req = urllib.request.Request(
    url,
    data=data,
    method="POST",
    headers={
        "Authorization": "Bearer " + os.environ["GH_TOKEN"],
        "Accept": "application/vnd.github+json",
        "Content-Type": "application/json",
    },
)
urllib.request.urlopen(req)
print("failure comment posted")
