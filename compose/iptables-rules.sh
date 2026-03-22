#!/bin/bash
# True Zero-Trust Fail-Closed Mode.
# We lock the doors BEFORE we start looking for the guardian.

echo "🔐 Trusting Local Egress Guardian certificate..."
# Wait up to 10s for the local mitmproxy to generate its certificate
for i in {1..10}; do
    CERT_FILE="/home/mitm-proxy/.mitmproxy/mitmproxy-ca-cert.pem"
    if [ -f "$CERT_FILE" ]; then
        cp "$CERT_FILE" /usr/local/share/ca-certificates/mitmproxy.crt
        update-ca-certificates --fresh > /dev/null
        echo "✅ Certificate trusted."
        break
    fi
    sleep 1
done

echo "🔒 INITIAL LOCKDOWN: Blocking web traffic until monitor is ready..."

# 1. Allow indispensable traffic (local loopback and DNS)
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# 2. Allow the mitm-proxy user to talk to the internet (Infinite Loop Protector)
PROXY_UID=$(id -u mitm-proxy)
iptables -A OUTPUT -m owner --uid-owner $PROXY_UID -j ACCEPT

# 3. REDIRECT all other HTTP/HTTPS traffic to the local monitor
iptables -t nat -A OUTPUT -p tcp -m owner ! --uid-owner $PROXY_UID --dport 80 -j REDIRECT --to-port 8080
iptables -t nat -A OUTPUT -p tcp -m owner ! --uid-owner $PROXY_UID --dport 443 -j REDIRECT --to-port 8080

# 4. FAIL-CLOSED: Block 80/443 for everyone else if they somehow bypass redirection
iptables -A OUTPUT -p tcp --dport 80 -j REJECT
iptables -A OUTPUT -p tcp --dport 443 -j REJECT

# 5. HARDEN CONFIG PERMISSIONS (Defense in Depth)
# We restrict the parent directories so the 'openclaw' user cannot even enter them.
echo "🛡️  Hardening configuration permissions..."
chown -R predicate:predicate /etc/predicate && chmod 700 /etc/predicate
chown -R mitm-proxy:mitm-proxy /etc/mitmproxy && chmod 750 /etc/mitmproxy

echo "Done. All web traffic is now routed through the local egress guardian."
