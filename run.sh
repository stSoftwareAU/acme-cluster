#!/bin/bash
set -e
acme_tiny (){

    rm -f /tmp/acme.crt
    set +e
    python acme_tiny.py --account-key ~/keys/account.key --csr $CSR --acme-dir ~/challenges > /tmp/acme.crt

    set -e
    if [ -s /tmp/acme.crt ]; then
        mv /tmp/acme.crt $PEM
       #cat /tmp/acme.crt $CROSS > $PEM
    else
       echo "could not create cert for ${domain}"
    fi
}

defaults() {

    mkdir -p ~/csr
    mkdir -p ~/keys
    mkdir -p ~/certs
    mkdir -p ~/challenges

    t=`date +%Y%m%d%H%M`
    let u=$t-1000000

    MONTHAGO=/tmp/MONTHAGO
    touch -t "$u" $MONTHAGO

    if [ -f  ~/env.sh ]; then
       . ~/env.sh
    fi

    if [[ ! $MOUNT = *[!\ ]* ]]; then
       MOUNT="www"
    fi
    
    if [ ! -f ~/keys/account.key ]; then
        openssl genrsa 4096 > ~/keys/account.key
    fi

    if [ ! -f ~/keys/domain.key ]; then
        #generate a domain private key (if you haven't already)
        openssl genrsa 4096 > ~/keys/domain.key
    fi


    if [ ! -f ~/keys/lets-encrypt-x3-cross-signed.pem ]; then
        cd ~/keys
        wget -N https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem
        cd ~
    fi
}

create_site(){
    tmpfile=$(mktemp /tmp/site.XXXXXX)
    
    cat >$tmpfile << EOF

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
    </VirtualHost>
</IfModule>
EOF4

    mv $tmpfile $SITE
}

defaults

cd ~/acme-cluster

CROSS=~/keys/lets-encrypt-x3-cross-signed.pem

if [ $CROSS -ot $MONTHAGO ]; then
    wget -O - https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem > /tmp/lets-encrypt-x3-cross-signed.pem
    if [ -s /tmp/lets-encrypt-x3-cross-signed.pem ]; then
        mv /tmp/lets-encrypt-x3-cross-signed.pem ~/keys/
    fi
fi

domains=$(cat ~/domains.txt)
rm -f ~/challenges/*
mkdir -p ~/sites

for domain in $domains
do
    CSR=~/csr/${domain}.csr
    if [ ! -s $CSR ]; then
        echo "create a certificate signing request (CSR) for: ${domain}"
        
        if [[ ${domain} =~ ([^\.]+\.){3,}.+ ]]; then
            echo "Single domain: ${domain}"
            openssl req -new -sha256 -key ~/keys/domain.key -subj "/CN=${domain}" > $CSR
        else
            echo "multiple domains: www.${domain} & ${domain}"
            openssl req -new -sha256 -key ~/keys/domain.key -subj "/" -reqexts SAN -config <(cat /etc/ssl/openssl.cnf <(printf "[SAN]\nsubjectAltName=DNS:${domain},DNS:www.${domain}")) > $CSR
        fi
    fi

    PEM=~/certs/${domain}.pem
    if [ ! -s $PEM ]; then
       echo "create cert for: ${domain}"
       acme_tiny
    else
        if [[ $CSR -nt $PEM ]]; then
            echo "$CSR is newer than $PEM"
            acme_tiny
        else 
            if [ $PEM -ot $MONTHAGO ]; then
                echo "renew cert for: ${domain}"
                acme_tiny
            fi
        fi
    fi
    SITE=~/sites/100-${domain}.conf
    if [ -f $PEM ]; then
        if [ ! -f $SITE ]; then
            echo "create site for: ${domain}"
            create_site
        fi
    fi
done

~/sync.sh
