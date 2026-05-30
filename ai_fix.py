import os, subprocess, sys, requests, re

API_KEY = os.environ.get("GEMINI_API_KEY")
LOG_FILE = "build.log"

if not API_KEY:
    print("❌ لا يوجد GEMINI_API_KEY")
    sys.exit(1)

# لا تعمل إذا كان آخر commit يحوي [AI Fix]
last_msg = subprocess.getoutput("git log -1 --pretty=%B")
if "[AI Fix]" in last_msg:
    print("ℹ️ تم تطبيق إصلاح تلقائي سابقاً. التوقف.")
    sys.exit(0)

if not os.path.exists(LOG_FILE):
    print("❌ ملف build.log غير موجود")
    sys.exit(1)

with open(LOG_FILE, "r") as f:
    log_content = f.read()

url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={API_KEY}"
prompt = f"""
You are a Flutter/Android build expert. A build failed with the following log.
Analyze the error carefully. Provide ONLY the exact file modifications needed to fix the build.
Return a unified diff patch (diff --git ...) that can be applied with `git apply`.
If the error is a Kotlin version mismatch, adjust android/build.gradle (ext.kotlin_version) or resolutionStrategy.
If minSdkVersion issue, change android/app/build.gradle.
Ensure the patch applies cleanly on the current repository.
Do not include any explanation, only the raw patch.

Build log:
{log_content}
"""
data = {
    "contents": [{"parts": [{"text": prompt}]}]
}
resp = requests.post(url, json=data)
if resp.status_code != 200:
    print(f"❌ Gemini API error: {resp.status_code} {resp.text}")
    sys.exit(1)

try:
    text_response = resp.json()["candidates"][0]["content"]["parts"][0]["text"]
except (KeyError, IndexError):
    print("❌ No valid response from Gemini.")
    sys.exit(1)

patch_match = re.search(r"```(?:diff)?\n(.*?)```", text_response, re.DOTALL)
if patch_match:
    patch = patch_match.group(1)
else:
    patch = text_response

with open("fix.patch", "w") as f:
    f.write(patch)

result = subprocess.run(["git", "apply", "--check", "fix.patch"], capture_output=True)
if result.returncode != 0:
    print("❌ لا يمكن تطبيق الـ patch:")
    print(result.stderr.decode())
    sys.exit(1)

subprocess.run(["git", "apply", "fix.patch"], check=True)
print("✅ تم تطبيق الإصلاح. سيتم commit و push.")
