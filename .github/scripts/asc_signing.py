#!/usr/bin/env python3
"""Manual App Store signing for Mission Control Chat, driven by the App Store Connect API.

Why: on the Xcode 27 runner, xcodebuild's own API-key provisioning (-allowProvisioningUpdates) fails with
"Authentication failed", while the same key works fine when called directly. So this script does the
provisioning itself and xcodebuild only signs with what is installed locally.

  setup        bundle IDs + capabilities, a temporary Apple Distribution certificate (p12 into $RUNNER_TEMP),
               one App Store profile per target (installed), signing settings added to each target.yml.
  entitlements run after xcodegen: compares each generated .entitlements with what its profile grants,
               fixes aps-environment, drops keys Apple won't grant, fails clearly if the app group is missing.
  revoke       revokes the temporary certificate (builds already uploaded stay valid).

Prints names and Apple's answers, never key material.
"""
import base64, json, os, plistlib, re, secrets, sys, time
import jwt, requests
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

API = "https://api.appstoreconnect.apple.com/v1/"
BASE = "com.wearemissioncontrol.chat"
GROUP = "group." + BASE
TARGETS = {"ElementX": BASE, "NSE": BASE + ".nse", "ShareExtension": BASE + ".shareextension"}
CAPS = {"ElementX": ["PUSH_NOTIFICATIONS", "APP_GROUPS"], "NSE": ["APP_GROUPS"], "ShareExtension": ["APP_GROUPS"]}
TMP = os.environ.get("RUNNER_TEMP", "/tmp")
STATE = os.path.join(TMP, "asc_signing.json")
PROFILE_DIR = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")


def profile_name(ident):
    return "MC Chat CI " + ident


def token():
    k = os.environ["ASC_KEY_ID"].strip()
    i = os.environ["ASC_ISSUER_ID"].strip()
    p = os.environ["ASC_KEY_P8"].strip() + "\n"
    now = int(time.time())
    return jwt.encode({"iss": i, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}, p,
                      algorithm="ES256", headers={"kid": k})


def call(method, path, body=None, params=None, fatal=True):
    r = requests.request(method, API + path, json=body, params=params,
                         headers={"Authorization": "Bearer " + token()}, timeout=60)
    if r.status_code >= 300:
        msg = f"{method} {path} -> {r.status_code} {r.text[:700]}"
        if fatal:
            print("::error::" + msg)
            sys.exit(1)
        print("warning: " + msg)
        return None
    return r.json() if r.text else {}


def bundle_id(ident):
    d = call("GET", "bundleIds", params={"filter[identifier]": ident, "limit": 200})["data"]
    for b in d:
        if b["attributes"]["identifier"] == ident:
            return b["id"]
    name = "MC Chat " + (ident[len(BASE) + 1:] or "app")
    b = call("POST", "bundleIds", {"data": {"type": "bundleIds", "attributes": {
        "identifier": ident, "name": name.replace(".", " "), "platform": "IOS"}}})["data"]
    print(f"  created bundle id {ident}")
    return b["id"]


def setup():
    devs = call("GET", "devices", params={"limit": 200})["data"]
    print(f"devices registered: {len(devs)}: " + ", ".join(
        f"{d['attributes']['name']} ({d['attributes'].get('model') or d['attributes'].get('deviceClass')}, {d['attributes']['status']})" for d in devs))

    ids = {}
    for t, ident in TARGETS.items():
        bid = bundle_id(ident)
        ids[t] = bid
        have = {c["attributes"]["capabilityType"] for c in
                call("GET", f"bundleIds/{bid}/bundleIdCapabilities")["data"]}
        print(f"  {ident}: capabilities {sorted(have)}")
        for cap in CAPS[t]:
            if cap not in have:
                ok = call("POST", "bundleIdCapabilities", {"data": {"type": "bundleIdCapabilities",
                          "attributes": {"capabilityType": cap},
                          "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}}}}}, fatal=False)
                print(f"    enable {cap}: {'ok' if ok else 'refused'}")

    # Temporary distribution certificate; revoked by `revoke` at the end of the job.
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = (x509.CertificateSigningRequestBuilder()
           .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "MC Chat CI"),
                                    x509.NameAttribute(NameOID.COUNTRY_NAME, "GB")]))
           .sign(key, hashes.SHA256()))
    csr_pem = csr.public_bytes(serialization.Encoding.PEM).decode()
    c = call("POST", "certificates", {"data": {"type": "certificates", "attributes": {
        "csrContent": csr_pem, "certificateType": "DISTRIBUTION"}}}, fatal=False)
    if c is None:
        c = call("POST", "certificates", {"data": {"type": "certificates", "attributes": {
            "csrContent": csr_pem, "certificateType": "IOS_DISTRIBUTION"}}})
    cert_id = c["data"]["id"]
    cert = x509.load_der_x509_certificate(base64.b64decode(c["data"]["attributes"]["certificateContent"]))
    identity = cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)[0].value
    print(f"temporary certificate: {c['data']['attributes']['certificateType']} '{identity}'")
    pw = secrets.token_hex(16)
    # Legacy 3DES/SHA1 PKCS12: macOS `security import` can't read OpenSSL 3's default AES p12.
    enc = (serialization.PrivateFormat.PKCS12.encryption_builder().kdf_rounds(50000)
           .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC).hmac_hash(hashes.SHA1()).build(pw.encode()))
    with open(os.path.join(TMP, "dist.p12"), "wb") as f:
        f.write(pkcs12.serialize_key_and_certificates(b"MC Chat CI", key, cert, None, enc))

    os.makedirs(PROFILE_DIR, exist_ok=True)
    profiles = {}
    for t, ident in TARGETS.items():
        name = profile_name(ident)
        for old in call("GET", "profiles", params={"filter[name]": name, "limit": 50})["data"]:
            call("DELETE", f"profiles/{old['id']}", fatal=False)
        p = call("POST", "profiles", {"data": {"type": "profiles",
                 "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
                 "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": ids[t]}},
                                   "certificates": {"data": [{"type": "certificates", "id": cert_id}]}}}})["data"]
        raw = base64.b64decode(p["attributes"]["profileContent"])
        with open(os.path.join(PROFILE_DIR, p["attributes"]["uuid"] + ".mobileprovision"), "wb") as f:
            f.write(raw)
        ents = plist_of(raw)["Entitlements"]
        profiles[t] = {"name": name, "entitlements": ents}
        print(f"  profile '{name}': grants {sorted(ents)}; groups {ents.get('com.apple.security.application-groups')}")

        # Signing settings for this target only (command-line overrides would also hit the SPM packages).
        spec = f"{t}/SupportingFiles/target.yml"
        s = open(spec).read()
        m = re.search(r"\n    settings:\n      base:\n", s)
        assert m, spec
        add = (f"        CODE_SIGN_STYLE: Manual\n        CODE_SIGN_IDENTITY: \"{identity}\"\n"
               f"        PROVISIONING_PROFILE_SPECIFIER: \"{name}\"\n")
        open(spec, "w").write(s[:m.end()] + add + s[m.end():])

    json.dump({"cert_id": cert_id, "p12_password": pw, "identity": identity, "profiles": profiles},
              open(STATE, "w"), default=str)
    with open(os.path.join(TMP, "ExportOptions.plist"), "wb") as f:
        plistlib.dump({"method": "app-store-connect", "destination": "export", "teamID": os.environ["TEAM_ID"],
                       "signingStyle": "manual", "signingCertificate": identity,
                       "provisioningProfiles": {ident: profile_name(ident) for ident in TARGETS.values()},
                       "manageAppVersionAndBuildNumber": False, "uploadSymbols": True,
                       "testFlightInternalTestingOnly": False}, f)


def plist_of(raw):
    a, b = raw.index(b"<?xml"), raw.index(b"</plist>") + len(b"</plist>")
    return plistlib.loads(raw[a:b])


def entitlements():
    st = json.load(open(STATE))
    missing_group = []
    for t in TARGETS:
        path = f"{t}/SupportingFiles/{t}.entitlements"
        d = plistlib.load(open(path, "rb"))
        grants = st["profiles"][t]["entitlements"]
        for k in list(d):
            if k == "aps-environment":
                if k in grants:
                    d[k] = grants[k]
                else:
                    print(f"  {t}: profile has no push; dropping aps-environment"); d.pop(k)
            elif k == "com.apple.security.application-groups":
                if GROUP not in (grants.get(k) or []):
                    missing_group.append(t)
            elif k in ("keychain-access-groups", "com.apple.security.app-sandbox", "com.apple.security.network.client"):
                pass
            elif k not in grants:
                print(f"  {t}: Apple doesn't grant {k}; dropping it"); d.pop(k)
        plistlib.dump(d, open(path, "wb"))
        print(f"  {t}: signing with {sorted(d)}")
    if missing_group:
        print(f"::error::APP GROUP NOT ASSIGNED: {GROUP} is not in the profiles for {missing_group}. "
              "It has to be created on developer.apple.com (Identifiers > App Groups) and ticked on those App IDs; "
              "the API key can't do that.")
        sys.exit(3)


def revoke():
    if not os.path.exists(STATE):
        print("nothing to revoke"); return
    cid = json.load(open(STATE))["cert_id"]
    call("DELETE", f"certificates/{cid}", fatal=False)
    print("temporary certificate revoked")


if __name__ == "__main__":
    {"setup": setup, "entitlements": entitlements, "revoke": revoke}[sys.argv[1]]()
