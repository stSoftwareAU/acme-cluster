#!/bin/bash
set -e
acme_tiny (){

    rm -f /tmp/acme.crt
    set +e
    python acme_tiny.py --account-key keys/account.key --csr $CSR --acme-dir challenges > /tmp/acme.crt

    set -e
    if [ -s /tmp/acme.crt ]; then
        mv /tmp/acme.crt $PEM
       #cat /tmp/acme.crt $CROSS > $PEM
    else
       echo "could not create cert for ${domain}"
    fi
}

defaults() {
    if [ -f  ~/env.sh ]; then
       . ~/env.sh
    fi

    if [[ ! $MOUNT = *[!\ ]* ]]; then
       MOUNT="www"
    fi
}

create_site(){
    tmpfile=$(mktemp /tmp/site.XXXXXX)
    
    cat >$tmpfile << EOF
Alias /.well-known/acme-challenge/ /home/letsencrypt/challenges/
<Directory /home/letsencrypt/challenges>
   AllowOverride None
   Require all granted
   Satisfy Any
</Directory>

<VirtualHost *:80>
        ServerName ${domain}
EOF
    if [[ ! "${domain}" =~ ".*[a-z0-9A-Z\-_]+\.[a-z0-9A-Z\-_]+\.[a-z0-9A-Z\-_]+\.[a-z0-9A-Z\-_]+" ]]; then
        cat >>$tmpfile << EOF1
        ServerAlias www.${domain}
EOF1
    fi
    
    cat >>$tmpfile << EOF2
        JkMount /* ${MOUNT}
        JkUnMount /.well-known/acme-challenge/* ${MOUNT}
        ErrorLog \${APACHE_LOG_DIR}/${domain}/error.log
        CustomLog \${APACHE_LOG_DIR}/${domain}/access.log combined
</VirtualHost>
    
<IfModule mod_ssl.c>
    <VirtualHost *:443>
        ServerName ${domain}
EOF2

    if [[ ! "${domain}" =~ ".*[a-z0-9A-Z\-_]+\.[a-z0-9A-Z\-_]+\.[a-z0-9A-Z\-_]+\.[a-z0-9A-Z\-_]+" ]]; then
        cat >> $tmpfile << EOF3
        ServerAlias www.${domain}
EOF3
    fi

    cat >> $tmpfile << EOF4
        JkMount /* ${MOUNT}
        SSLEngine on
        SSLCertificateFile /home/letsencrypt/certs/${domain}.pem
        SSLCertificateKeyFile /home/letsencrypt/keys/domain.key
        SSLCertificateChainFile /home/letsencrypt/keys/lets-encrypt-x3-cross-signed.pem

        Header always set Strict-Transport-Security "max-age=31536000"

        ErrorLog \${APACHE_LOG_DIR}/${domain}/error.log
        CustomLog \${APACHE_LOG_DIR}/${domain}/access.log combined
    </VirtualHost>
</IfModule>
EOF4

    mv $tmpfile $SITE
}

defaults

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
mkdir -p sites

for domain in $domains
do
    CSR=csr/${domain}.csr
    if [ ! -f $CSR ]; then
        echo "create a certificate signing request (CSR) for: ${domain}"
        
        if [[ "${domain}" =~ ".*[a-z0-9A-Z\-_]+\.[a-z0-9A-Z\-_]+\.[a-z0-9A-Z\-_]+\.[a-z0-9A-Z\-_]+" ]]; then
            echo "Single domain: ${domain}"
            openssl req -new -sha256 -key keys/domain.key -subj "/CN=${domain}" > $CSR
        else
            echo "multiple domains: www.${domain} & ${domain}"
            openssl req -new -sha256 -key keys/domain.key -subj "/" -reqexts SAN -config <(cat /etc/ssl/openssl.cnf <(printf "[SAN]\nsubjectAltName=DNS:${domain},DNS:www.${domain}")) > $CSR
        fi
    fi

    PEM=certs/${domain}.pem
    if [ ! -f $PEM ]; then
       echo "create cert for: ${domain}"
       acme_tiny
    else
        if [[ $CSR -nt $PEM ]]; then
            echo "$CSR is newer than $PEM"
            acme_tiny
        else 
            if test `find "$PEM" -mtime 30`
            then
                echo "renew cert for: ${domain}"
                acme_tiny
            fi
        fi
    fi
    SITE=sites/100-${domain}.conf
    if [ -f $PEM ]; then
        if [ ! -f $SITE ]; then
            echo "create site for: ${domain}"
            create_site
        fi
    fi
done

./sync.sh
