#!/bin/bash
set -e
acme_tiny (){

    rm -f /tmp/acme.crt
    set +e
    python acme_tiny.py --account-key keys/account.key --csr $CSR --acme-dir challenges > /tmp/acme.crt

    set -e
    if [ -s /tmp/acme.crt ]; then
       cat /tmp/acme.crt $CROSS > $PEM
    else
       echo "could not create cert for ${domain}"
    fi
}

cd

CROSS=keys/lets-encrypt-x3-cross-signed.pem

if test `find "$CROSS" -mtime 30`
then
    wget -O - https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem > /tmp/lets-encrypt-x3-cross-signed.pem
    if [ -s /tmp/lets-encrypt-x3-cross-signed.pem ]; then
        mv /tmp/lets-encrypt-x3-cross-signed.pem keys/
    fi
fi


domains=$(cat domains.txt)
rm -f challenges/*

for domain in $domains
do
    CSR=csr/${domain}.csr
    if [ ! -f $CSR ]; then
       echo "create a certificate signing request (CSR) for: ${domain}"
       openssl req -new -sha256 -key keys/domain.key -subj "/CN=${domain}" > $CSR

    fi

    PEM=certs/${domain}.pem
    if [ ! -f $PEM ]; then
       echo "create cert for: ${domain}"
       acme_tiny
    else
        if test `find "$PEM" -mtime 30`
        then
            echo "renew cert for: ${domain}"
            acme_tiny
        fi
    fi
done

./sync.sh
