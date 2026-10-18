"""Summarise a Unity Test Framework NUnit XML result file (python -I Tools/test_summary.py <xml>)."""
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
try:
    root = ET.parse(path).getroot()
except Exception as e:  # noqa
    print("== no test result file:", e)
    sys.exit(0)
print("== tests: result=%s total=%s passed=%s failed=%s skipped=%s duration=%ss" % (
    root.get("result"), root.get("total"), root.get("passed"), root.get("failed"), root.get("skipped"), root.get("duration")))
for tc in root.iter("test-case"):
    res = tc.get("result")
    if res == "Passed" and "-v" not in sys.argv:
        continue
    msg = ""
    f = tc.find("failure")
    if f is not None:
        m = f.find("message")
        msg = (m.text or "").strip().replace("\n", " ")[:300] if m is not None else ""
    print("  [%s] %s (%ss) %s" % (res, tc.get("fullname"), tc.get("duration"), msg))
