"""Upload dice glb files to Roblox as Models (group-owned) through Open Cloud and record asset ids.
Usage: python tools/upload_dice.py <out.json> <name>=<file.glb> [...]   (key from ROBLOX_API_KEY, group from ROBLOX_CREATOR_GROUP_ID)"""
import json
import mimetypes  # noqa: F401
import os
import sys
import time
import urllib.request
import uuid

KEY, GROUP = os.environ["ROBLOX_API_KEY"], os.environ["ROBLOX_CREATOR_GROUP_ID"]
BASE = "https://apis.roblox.com/assets/v1"


def call(req):
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read())


def upload(name, path):
    boundary = uuid.uuid4().hex
    meta = {"assetType": "Model", "displayName": name, "description": "Dice Defenders die", "creationContext": {"creator": {"groupId": GROUP}}}
    body = b"".join([
        f'--{boundary}\r\nContent-Disposition: form-data; name="request"\r\nContent-Type: application/json\r\n\r\n{json.dumps(meta)}\r\n'.encode(),
        f'--{boundary}\r\nContent-Disposition: form-data; name="fileContent"; filename="{os.path.basename(path)}"\r\nContent-Type: model/gltf-binary\r\n\r\n'.encode(),
        open(path, "rb").read(), f"\r\n--{boundary}--\r\n".encode()])
    req = urllib.request.Request(f"{BASE}/assets", data=body, method="POST",
                                 headers={"x-api-key": KEY, "Content-Type": f"multipart/form-data; boundary={boundary}"})
    op = call(req)
    opid = op["path"].split("/")[-1]
    for _ in range(60):
        time.sleep(2)
        done = call(urllib.request.Request(f"{BASE}/operations/{opid}", headers={"x-api-key": KEY}))
        if done.get("done"):
            return done["response"]["assetId"]
    raise TimeoutError(name)


if __name__ == "__main__":
    out = sys.argv[1]
    results = json.load(open(out)) if os.path.exists(out) else {}
    for arg in sys.argv[2:]:
        name, path = arg.split("=", 1)
        if name in results:
            continue
        for attempt in range(6):  # parallel workers get 403/429 bursts from the asset API: back off and retry
            try:
                results[name] = upload(name, path)
                print(name, results[name], flush=True)
                break
            except Exception as exc:  # noqa: BLE001  shortcut: log and continue, rerun resumes from the json
                print("RETRY", name, repr(exc)[:120], flush=True)
                time.sleep(15 * (attempt + 1))
        json.dump(results, open(out, "w"), indent=1)
