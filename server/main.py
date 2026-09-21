import json
import os
import shutil
import subprocess
import sys
import time
import atexit
import asyncio
import requests as pyrequests
from aiohttp import web

LIBRETRANSLATE_PORT = 5000
LIBRETRANSLATE_URL = f"http://127.0.0.1:{LIBRETRANSLATE_PORT}/translate"
LOAD_ONLY = "en,ru"  # "en,ru,uk,it,bg,es,de,pl,fr,ro,pt"

lt_process = None

def find_libretranslate_exe():
    found = shutil.which("libretranslate")
    if found:
        return found

    python_dir = os.path.dirname(sys.executable)
    candidates = [
        os.path.join(python_dir, "Scripts", "libretranslate.exe"),
        os.path.join(python_dir, "libretranslate.exe"),
    ]
    for path in candidates:
        if os.path.isfile(path):
            return path

    appdata = os.environ.get("APPDATA")
    if appdata:
        py_tag = f"Python{sys.version_info.major}{sys.version_info.minor}"
        guess = os.path.join(appdata, "Python", py_tag, "Scripts", "libretranslate.exe")
        if os.path.isfile(guess):
            return guess

    return None

def start_libretranslate():
    global lt_process
    exe_path = find_libretranslate_exe()
    if not exe_path:
        print("Could not locate libretranslate.exe automatically.")
        print("Run: pip show -f libretranslate   and check the Location: line,")
        print("then set LIBRETRANSLATE_EXE manually near the top of this file.")
        sys.exit(1)

    print(f"Starting LibreTranslate from: {exe_path}")
    lt_process = subprocess.Popen(
        [exe_path, "--port", str(LIBRETRANSLATE_PORT), "--load-only", LOAD_ONLY],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    for attempt in range(60):
        try:
            pyrequests.get(f"http://127.0.0.1:{LIBRETRANSLATE_PORT}/languages", timeout=1)
            print("LibreTranslate is ready.")
            return
        except pyrequests.exceptions.RequestException:
            time.sleep(1)
    print("LibreTranslate did not start in time.")
    sys.exit(1)

def stop_libretranslate():
    if lt_process and lt_process.poll() is None:
        print("Stopping LibreTranslate...")
        lt_process.terminate()
        try:
            lt_process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            lt_process.kill()

atexit.register(stop_libretranslate)

async def handle(request):
    headers = {"Content-Type": "application/json; charset=utf-8"}

    if request.method not in ['POST', 'GET']:
        return web.Response(headers=headers, text=json.dumps({"success": False, "error": "Method not allowed"}))

    source = target = text = None
    texts = []  # every "text" field of a form POST; more than one means a batch request
    if request.method == "POST":
        if 'json' in request.headers.get("Content-Type").lower():
            try:
                data = await request.json()
            except:
                return web.Response(status=404, headers=headers, text=json.dumps({"success": False, "error": "You've specified invalid JSON"}))
            source = data['source']
            target = data['target']
            text = data['text']
        else:
            data = await request.post()
            source = data.get('source', None)
            target = data.get('target', None)
            text = data.get('text', None)
            texts = data.getall('text', [])
    elif request.method == 'GET':
        data = request.query
        source = data.get('source', None)
        target = data.get('target', None)
        text = data.get('text', None)

    if 'source' in data and 'target' in data and 'text' in data:
        try:
            src = source if source and source.lower() != "auto" else "auto"
            batch = len(texts) > 1
            payload = {"q": texts if batch else text, "source": src, "target": target, "format": "text"}
            # run the blocking HTTP call in a thread so the web server stays responsive
            resp = await asyncio.get_running_loop().run_in_executor(
                None, lambda: pyrequests.post(LIBRETRANSLATE_URL, json=payload, timeout=30 if batch else 10))
            resp.raise_for_status()
            translated = resp.json()["translatedText"]
            if batch:  # a list of translations, in the same order as the "text" fields
                return web.Response(headers=headers, text=json.dumps({"success": True, "texts": translated}))
            return web.Response(headers=headers, text=json.dumps({"success": True, "text": translated}))
        except Exception as e:
            return web.Response(status=500, headers=headers, text=json.dumps({"success": False, "error": str(e)}))
    else:
        return web.Response(status=404, headers=headers, text=json.dumps({"success": False, "error": "You've specified invalid data"}))

app = web.Application()
app.router.add_route('*', '/', handle)

if __name__ == "__main__":
    start_libretranslate()
    web.run_app(app, host='127.0.0.1', port=9550)
