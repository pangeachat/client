#!/usr/bin/env python3
"""End-to-end MatrixRTC check against the local stack.

Run:  python3 test/pangea/calls/e2e/matrixrtc_local_e2e.py
Needs: pangea up (Synapse :8008) plus the MatrixRTC compose services
       (livekit :7880, lk-jwt-service :7980). Exits non-zero on any failure.

Not part of `flutter test` — it drives live servers on purpose. The unit suite proves
our logic; this proves the wiring between four processes, which is where this feature
actually breaks.

Drives the protocol the way two Pangea clients will: two real users, a real DM, real
com.famedly.call.member state, real OpenID->JWT exchange, real LiveKit rooms. No mocks.
"""
import json, sys, urllib.request, urllib.error, uuid

SYN = "http://localhost:8008"
JWT = "http://localhost:7980"
FOCUS = "http://localhost:7980"

def req(method, url, body=None, token=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Content-Type", "application/json")
    if token: r.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(r, timeout=25) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try: return e.code, json.loads(raw)
        except Exception: return e.code, {"raw": raw[:300]}

def login(user, pw):
    s, b = req("POST", f"{SYN}/_matrix/client/v3/login", {
        "type": "m.login.password",
        "identifier": {"type": "m.id.user", "user": user},
        "password": pw})
    assert s == 200, f"login {user}: {s} {b}"
    return b["access_token"], b["user_id"], b["device_id"]

def register(user, pw):
    s, b = req("POST", f"{SYN}/_matrix/client/v3/register", {
        "username": user, "password": pw, "auth": {"type": "m.login.dummy"},
        "inhibit_login": False})
    if s == 200: return b["access_token"], b["user_id"], b["device_id"]
    return login(user, pw)

fails = []
def check(name, ok, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'}  {name}" + (f"  — {detail}" if detail else ""))
    if not ok: fails.append(name)

print("== participants ==")
a_tok, a_id, a_dev = login("learner", "learnerpass")
print(f"  A: {a_id} ({a_dev})")
b_tok, b_id, b_dev = register("calltester", "calltesterpass")
print(f"  B: {b_id} ({b_dev})")

print("\n== a direct message room ==")
s, b = req("POST", f"{SYN}/_matrix/client/v3/createRoom",
           {"preset": "trusted_private_chat", "invite": [b_id], "is_direct": True}, a_tok)
assert s == 200, f"createRoom: {s} {b}"
room = b["room_id"]
print(f"  room: {room}")
s, _ = req("POST", f"{SYN}/_matrix/client/v3/rooms/{room}/join", {}, b_tok)
check("both users joined the room", s == 200)

print("\n== each participant gets a LiveKit grant ==")
grants = {}
for who, tok, uid, dev in (("A", a_tok, a_id, a_dev), ("B", b_tok, b_id, b_dev)):
    s, oidc = req("POST", f"{SYN}/_matrix/client/v3/user/{uid}/openid/request_token", {}, tok)
    assert s == 200, f"openid {who}: {s} {oidc}"
    s, g = req("POST", f"{JWT}/sfu/get", {
        "room": room,
        "openid_token": {"access_token": oidc["access_token"],
                         "token_type": oidc["token_type"],
                         "matrix_server_name": oidc["matrix_server_name"]},
        "device_id": dev})
    check(f"{who} received a LiveKit grant", s == 200 and "jwt" in g,
          g.get("error", f"url={g.get('url')}"))
    grants[who] = g

print("\n== both grants address the SAME LiveKit room ==")
def room_of(jwt):
    import base64
    p = jwt.split(".")[1]; p += "=" * (-len(p) % 4)
    return json.loads(base64.urlsafe_b64decode(p))["video"]["room"]
if all("jwt" in g for g in grants.values()):
    ra, rb = room_of(grants["A"]["jwt"]), room_of(grants["B"]["jwt"])
    check("same SFU room for both participants", ra == rb, ra[:24] + "...")
    check("grants carry distinct identities",
          json.loads(__import__("base64").urlsafe_b64decode(
              grants["A"]["jwt"].split(".")[1] + "=="))["sub"] !=
          json.loads(__import__("base64").urlsafe_b64decode(
              grants["B"]["jwt"].split(".")[1] + "=="))["sub"])

print("\n== MatrixRTC membership, as the SDK publishes it ==")
for who, tok, uid, dev in (("A", a_tok, a_id, a_dev), ("B", b_tok, b_id, b_dev)):
    content = {"memberships": [{
        "call_id": room, "application": "m.call", "scope": "m.room",
        "foci_active": [{"type": "livekit",
                         "livekit_service_url": FOCUS,
                         "livekit_alias": room}],
        "device_id": dev, "expires_ts": 0,
        "membershipID": uuid.uuid4().hex}]}
    s, r = req("PUT",
        f"{SYN}/_matrix/client/v3/rooms/{room}/state/com.famedly.call.member/{uid}",
        content, tok)
    check(f"{who} published call membership", s == 200, r.get("error", ""))

s, st = req("GET", f"{SYN}/_matrix/client/v3/rooms/{room}/state", None, a_tok)
members = [e for e in st if e.get("type") == "com.famedly.call.member"
           and e.get("content", {}).get("memberships")]
check("room state shows both participants in the call", len(members) == 2,
      f"{len(members)} membership event(s)")
if members:
    foci = members[0]["content"]["memberships"][0].get("foci_active", [])
    check("membership advertises the livekit focus",
          bool(foci) and foci[0].get("type") == "livekit",
          foci[0].get("livekit_service_url") if foci else "none")

print("\n" + ("ALL CHECKS PASSED" if not fails else f"FAILURES: {fails}"))
sys.exit(1 if fails else 0)
