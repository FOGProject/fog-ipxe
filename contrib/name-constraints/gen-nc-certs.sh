#!/bin/bash
#
# Generate the X.509 name-constraint test fixtures for iPXE's x509 self-test.
#
# The upstream test file embeds certificates as literal byte arrays with no
# record of how they were made.  These ones are generated, so that a future
# reader can see exactly which constraint each fixture is exercising and can
# regenerate them if the test needs to change.
#
# Hierarchy:
#
#   nc_root                              unconstrained self-signed root
#    +- nc_ca        permitted DNS:example.com, IP:10.0.0.0/8, pathlen:1
#    |   +- nc_leaf          DNS:host.example.com      must PASS
#    |   +- nc_leaf_exact    DNS:example.com           must PASS (exact match)
#    |   +- nc_leaf_bad      DNS:notexample.com        must FAIL (label boundary)
#    |   +- nc_leaf_ip       IP:10.1.2.3               must PASS
#    |   +- nc_leaf_ip_bad   IP:192.168.1.1            must FAIL
#    |   +- nc_leaf_ip6      IPv6 SAN                  must FAIL (v4-only subtree)
#    |   +- nc_leaf_mail     rfc822 only               must PASS (type unconstrained)
#    |   +- nc_subca         intermediate, no constraints of its own
#    |       +- nc_deep      DNS:deep.example.com      must PASS
#    |       +- nc_deep_bad  DNS:evil.com              must FAIL  <-- transitivity
#    +- nc_excl_ca   permitted DNS:example.com, excluded DNS:bad.example.com
#    |   +- nc_leaf_excl     DNS:bad.example.com       must FAIL (excluded wins)
#    +- nc_unsup_ca  permitted rfc822:example.com      must FAIL TO PARSE
#
# nc_deep_bad is the one that matters most: it is the case that a name
# constraint implementation checking only the immediate issuer would wrongly
# accept, because the constraint lives two levels up the chain.
#
set -euo pipefail

OUT="${1:-$(dirname "$(readlink -f "$BASH_SOURCE")")/out}"
rm -rf "$OUT"; mkdir -p "$OUT"
cd "$OUT"

# Validity window straddles the nctest_time used by the self-test.
NOTBEFORE="20200101000000Z"
NOTAFTER="20400101000000Z"

newkey() { openssl genrsa -out "$1.key" 2048 2>/dev/null; }

# $1 name  $2 subject CN  $3 extfile contents  $4 issuer (empty => self-signed)
mkcert() {
    local name="$1" cn="$2" ext="$3" issuer="${4:-}"
    newkey "$name"
    printf '%s\n' "$ext" > "$name.ext"
    # `openssl req -x509` takes extensions only via a config section, so the
    # self-signed root is made the same way as the rest: CSR, then sign.
    openssl req -new -key "$name.key" -out "$name.csr" -subj "/CN=$cn" 2>/dev/null
    if [[ -z $issuer ]]; then
        openssl x509 -req -in "$name.csr" -signkey "$name.key" \
            -set_serial "0x$(openssl rand -hex 8)" -out "$name.pem" \
            -extfile "$name.ext" \
            -not_before "$NOTBEFORE" -not_after "$NOTAFTER" 2>/dev/null
    else
        openssl x509 -req -in "$name.csr" -CA "$issuer.pem" -CAkey "$issuer.key" \
            -set_serial "0x$(openssl rand -hex 8)" -out "$name.pem" \
            -extfile "$name.ext" \
            -not_before "$NOTBEFORE" -not_after "$NOTAFTER" 2>/dev/null
    fi
    openssl x509 -in "$name.pem" -outform der -out "$name.der"
}

CA_EXT='basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash'

mkcert nc_root "NC test root CA" "$CA_EXT"

mkcert nc_ca "NC test constrained CA" \
"basicConstraints = critical,CA:TRUE,pathlen:1
keyUsage = critical,keyCertSign,cRLSign
nameConstraints = critical,permitted;DNS:example.com,permitted;IP:10.0.0.0/255.0.0.0" \
    nc_root

mkcert nc_excl_ca "NC test excluding CA" \
"basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
nameConstraints = critical,permitted;DNS:example.com,excluded;DNS:bad.example.com" \
    nc_root

# Refused at parse time: an rfc822Name subtree is a constraint we cannot enforce.
mkcert nc_unsup_ca "NC test unsupported CA" \
"basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
nameConstraints = critical,permitted;email:example.com" \
    nc_root

mkcert nc_subca "NC test sub CA" "$CA_EXT" nc_ca

LEAF='basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth'

# Every fixture below keeps a commonName that satisfies the DNS constraint
# unless the commonName is itself what is under test, so that each certificate
# exercises exactly one rule.  OpenSSL applies dNSName constraints to the
# commonName of an end entity, so a CN chosen carelessly makes a fixture fail
# for a reason other than the one it is named for.
mkcert nc_leaf       "host.example.com" "$LEAF
subjectAltName = DNS:host.example.com"        nc_ca
mkcert nc_leaf_exact "example.com"      "$LEAF
subjectAltName = DNS:example.com"             nc_ca
mkcert nc_leaf_bad   "notexample.com"   "$LEAF
subjectAltName = DNS:notexample.com"          nc_ca
mkcert nc_leaf_ip    "ip.example.com"   "$LEAF
subjectAltName = IP:10.1.2.3"                 nc_ca
mkcert nc_leaf_ip_bad "ipbad.example.com" "$LEAF
subjectAltName = IP:192.168.1.1"              nc_ca
mkcert nc_leaf_ip6   "ip6.example.com"  "$LEAF
subjectAltName = IP:fd00::1"                  nc_ca
mkcert nc_leaf_mail  "mail.example.com" "$LEAF
subjectAltName = email:someone@example.org"   nc_ca

# No subjectAltName at all.  x509_check_name() will accept the commonName as a
# host name, so the commonName has to be constrained or the constraint can be
# stepped around entirely.
mkcert nc_leaf_cn    "host.example.com" "$LEAF"     nc_ca
mkcert nc_leaf_cn_bad "evil.com"        "$LEAF"     nc_ca
mkcert nc_deep       "deep.example.com" "$LEAF
subjectAltName = DNS:deep.example.com"        nc_subca
mkcert nc_deep_bad   "evil.com"         "$LEAF
subjectAltName = DNS:evil.com"                nc_subca
mkcert nc_leaf_excl  "bad.example.com"  "$LEAF
subjectAltName = DNS:bad.example.com"         nc_excl_ca

echo "generated in $OUT:"
ls -1 *.der
