"""Lists user-facing string literals in the app sources (used by build_strings.py)."""
import re, pathlib, sys

ROOTS = ["iOS", "Watch", "Widgets", "WatchWidgets", "Shared"]
LIT = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
SKIP_LINE = re.compile(r'URL\(string|#Predicate|keychainAccount|setValue|static let model|httpMethod|case \.english: lang|case \.simplifiedChinese: lang|case \.traditionalChinese: lang|separator:|error\.localizedDescription')
STRIP = re.compile(r'(systemImage|systemName|forInfoDictionaryKey|forHTTPHeaderField|kind|identifier|origin|verbatim|forKey|suiteName|event|withIdentifiers)\s*:\s*"(?:[^"\\\n]|\\.)*"|Image\("[^"]*"\)|origin == "[^"]*"|\["[a-z]+"\]|"(event|at|snapshot)"\s*:')

def is_ui(s):
    if not s or "\\(" in s or s[0] in ",)": return False
    if re.fullmatch(r'[a-z0-9]+(\.[a-z0-9]+)+', s): return False       # SF symbol / dotted ids
    if re.fullmatch(r'[a-z][A-Za-z0-9]*', s) and s not in ("bpm",): return False   # camelCase keys
    if s.startswith(("vf.", "com.", "group.", "http", "VitalFlow.", "%.", "ml/")): return False
    if s in ("kcal", "min", "ml", "h", "%", "/100", "br/min", "7D", "30D", "90D", "1Y", "+250", "+500", " km", " ", "", "—", "HRV", "REM", "HIIT", "VitalFlow", "VO2 max", "250 ml", "kg", "ms", "ml/kg/min"):
        return s in ("kcal", "min", "ml", "br/min", "/100")  # unit-like strings shown via Text(unit)
    if s in ("POST", "Watch", "Logo", "English", "Simplified Chinese", "Traditional Chinese", "Demo"):
        return s == "Demo"
    return any(c.isalpha() for c in s)

def collect():
    out = {}
    for root in ROOTS:
        for p in sorted(pathlib.Path(root).rglob("*.swift")):
            for ln in p.read_text().splitlines():
                code = ln.split("//")[0] if '"' not in ln.split("//")[0][-1:] else ln
                if code.strip().startswith("//") or SKIP_LINE.search(code):
                    continue
                code = STRIP.sub("", code)
                for m in LIT.finditer(code):
                    s = m.group(1)
                    if is_ui(s):
                        out.setdefault(s.replace('\\"', '"'), str(p))
    # Keys produced by String(localized:) with interpolation.
    out.setdefault("The external assistant returned an error (%lld).", "iOS/Services/ExternalAssistant.swift")
    return out

if __name__ == "__main__":
    for k, v in collect().items():
        print(f"{v}\t{k}")
