DNS=$1

set -x

if [ -z "$1" ]
  then
    echo "No argument supplied"
	exit
fi

apt install -y certbot
certbot certonly --standalone -d ${DNS}
mkdir /etc/ssl/${DNS}
cat /etc/letsencrypt/live/${DNS}/fullchain.pem /etc/letsencrypt/live/${DNS}/privkey.pem > /etc/ssl/${DNS}/${DNS}.pem

apt install -y haproxy
cp /etc/haproxy/haproxy.cfg{,.orig}
echo "
frontend wwwhttp
        bind 0.0.0.0:80
        option forwardfor except 127.0.0.0/8
        reqadd X-Forwarded-Proto:\ http
        acl letsencrypt-acl path_beg /.well-known/acme-challenge/
                redirect scheme https if !letsencrypt-acl
        use_backend letsencrypt-backend if letsencrypt-acl
        default_backend explorerbackend

frontend wwwhttps
        # The SSL CRT file is a combination of the public certificate and the private key
        bind 0.0.0.0:443 ssl crt /etc/ssl/${DNS}/${DNS}.pem ciphers kEECDH+aRSA+AES:kRSA+AES:+AES256:RC4-SHA:!kEDH:!LOW:!EXP:!MD5:!aNULL:!eNULL no-sslv3
        option httplog
        option http-server-close
        option forwardfor except 127.0.0.0/8

        # stats in /stats
        stats enable
        stats hide-version
        stats uri     /stats
        stats realm   Haproxy\ Statistics
        stats auth    changeusername:changepassword

#       acl explorer  hdr(host)          explorer.btc.zeltrez.io
#       acl rates  hdr(host)          rates.btc.zeltrez.io
        acl explorer hdr(host)           ${DNS}
#       acl proxy hdr(host)     fra.proxy.zelcore.io

# http-request set-header X-Location-Path %[capture.req.uri] if explorer
## http-request replace-header X-Location-Path [^/]+/(.*) \1 if explorer
# http-request redirect code 307 location https://insight.bitpay.com%[hdr(X-Location-Path)] if explorer

        use_backend explorerbackend if explorer
#       use_backend ratesbackend if rates
#       use_backend proxybackend if proxy
        default_backend explorerbackend

backend explorerbackend
        mode http
        cookie SERVERID insert indirect nocache
        balance source
        server web1 localhost:3001 check cookie cookiename

#backend ratesbackend
#        mode http
#        cookie SERVERID insert indirect nocache
#        balance source
#        server web1 localhost:3333 check cookie cookiename

#backend proxybackend
        #mode http
        #cookie SERVERID insert indirect nocache
        #balance source
        #server web1 127.0.0.1:3838 check cookie cookiename

backend letsencrypt-backend
    server letsencrypt 127.0.0.1:8787" >> /etc/haproxy/haproxy.cfg
systemctl enable haproxy
systemctl start haproxy
