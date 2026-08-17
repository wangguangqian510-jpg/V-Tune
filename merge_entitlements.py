import plistlib
import sys


def main():
    if len(sys.argv) != 3:
        print("Usage: merge_entitlements.py <input.mobileprovision> <output.entitlements>")
        sys.exit(1)

    prov_path = sys.argv[1]
    out_path = sys.argv[2]

    with open(prov_path, "rb") as f:
        data = f.read()

    s = data.find(b"<?xml")
    e = data.rfind(b"</plist>") + len(b"</plist>")
    pl = plistlib.loads(data[s:e])

    ents = dict(pl.get("Entitlements", {}))
    ents["com.apple.security.files.user-selected.read-write"] = True
    ents["com.apple.security.files.downloads.read-write"] = True

    with open(out_path, "wb") as f:
        f.write(plistlib.dumps(ents))

    print("Merged entitlements keys:", list(ents.keys()))


if __name__ == "__main__":
    main()
