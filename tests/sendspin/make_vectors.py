"""Erzeugt einen festen KKpsk2-Mitschnitt (Server = Initiator) als Testvektor.

Aufruf: python3 make_vectors.py <pfad-zu-noiseprotocol> [suite] > vectors-….json
"""
import hashlib, json, sys
sys.path.insert(0, sys.argv[1])
from noise.connection import NoiseConnection, Keypair
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives import serialization as ser

def priv(seed):
    return hashlib.sha256(seed.encode()).digest()

def pub(p):
    return X25519PrivateKey.from_private_bytes(p).public_key().public_bytes(ser.Encoding.Raw, ser.PublicFormat.Raw)

suite = sys.argv[2] if len(sys.argv) > 2 else "25519_ChaChaPoly_SHA256"
srv_s, cli_s, srv_e, cli_e = priv("srv-s"), priv("cli-s"), priv("srv-e"), priv("cli-e")
psk = hashlib.sha256(b"sendspin-sentinel-psk-v1").digest()
prologue = b'{"type":"client/init","payload":{"x":1}}{"type":"server/init","payload":{"y":2}}'
name = ("Noise_KKpsk2_" + suite).encode()

def conn(initiator, s, e, rs):
    c = NoiseConnection.from_name(name)
    c.set_as_initiator() if initiator else c.set_as_responder()
    c.set_keypair_from_private_bytes(Keypair.STATIC, s)
    c.set_keypair_from_private_bytes(Keypair.EPHEMERAL, e)
    c.set_keypair_from_public_bytes(Keypair.REMOTE_STATIC, rs)
    c.set_prologue(prologue)
    c.set_psks(psks=[psk])
    c.start_handshake()
    return c

import warnings; warnings.simplefilter("ignore")
srv = conn(True, srv_s, srv_e, pub(cli_s))
cli = conn(False, cli_s, cli_e, pub(srv_s))
psk_id = hashlib.sha256(b"sendspin-psk-id-v1" + psk).digest()
import base64
b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()
m1_payload = json.dumps({"psk_id": b64(psk_id), "psk_category": "sn"}, separators=(",", ":")).encode()
m1 = srv.write_message(m1_payload)
assert cli.read_message(m1) == m1_payload
m2 = cli.write_message(b"{}")
assert srv.read_message(m2) == b"{}"
t1_plain = b"\x00" + b'{"type":"server/hello","payload":{"name":"Test"}}'
t1 = srv.encrypt(t1_plain)
t2 = srv.encrypt(b"\x00second")
t3_plain = b"\x00" + b'{"type":"client/hello","payload":{}}'
t3 = cli.encrypt(t3_plain)
print(json.dumps({k: v.hex() for k, v in dict(
    srv_s_pub=pub(srv_s), cli_s=cli_s, cli_s_pub=pub(cli_s), cli_e=cli_e, psk=psk,
    prologue=prologue, m1=m1, m1_payload=m1_payload, m2=m2,
    t1=t1, t1_plain=t1_plain, t2=t2, t3=t3, t3_plain=t3_plain,
    handshake_hash=cli.get_handshake_hash()).items()} | {"suite": suite}, indent=1))
