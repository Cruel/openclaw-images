#!/bin/bash
# True Zero-Trust Fail-Closed Mode.

# Create and flush our custom chains
iptables -t filter -N OPENCLAW_OUT 2>/dev/null || iptables -t filter -F OPENCLAW_OUT
iptables -t filter -N OPENCLAW_FWD 2>/dev/null || iptables -t filter -F OPENCLAW_FWD
iptables -t nat -N OPENCLAW_PREROUTE 2>/dev/null || iptables -t nat -F OPENCLAW_PREROUTE
iptables -t nat -N OPENCLAW_OUT 2>/dev/null || iptables -t nat -F OPENCLAW_OUT

# Fail-Closed IPv6 Bypass Prevention
# iptables ONLY catches IPv4. We MUST block IPv6 routing to prevent egress escapes.
if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -t filter -N OPENCLAW_V6_DROP 2>/dev/null || ip6tables -t filter -F OPENCLAW_V6_DROP
    ip6tables -t filter -D OUTPUT -j OPENCLAW_V6_DROP 2>/dev/null
    ip6tables -t filter -I OUTPUT 1 -j OPENCLAW_V6_DROP
    ip6tables -t filter -D FORWARD -j OPENCLAW_V6_DROP 2>/dev/null
    ip6tables -t filter -I FORWARD 1 -j OPENCLAW_V6_DROP
    
    ip6tables -A OPENCLAW_V6_DROP -o lo -j ACCEPT
    ip6tables -A OPENCLAW_V6_DROP -j REJECT
fi

# Hook into standard chains (idempotent: delete then insert)
iptables -t filter -D OUTPUT -j OPENCLAW_OUT 2>/dev/null
iptables -t filter -I OUTPUT 1 -j OPENCLAW_OUT

# Use DOCKER-USER for forward rules (Docker creates this chain)
iptables -t filter -N DOCKER-USER 2>/dev/null || true
iptables -t filter -D DOCKER-USER -j OPENCLAW_FWD 2>/dev/null
iptables -t filter -I DOCKER-USER 1 -j OPENCLAW_FWD
iptables -t filter -D FORWARD -j DOCKER-USER 2>/dev/null
iptables -t filter -I FORWARD 1 -j DOCKER-USER

iptables -t nat -D PREROUTING -j OPENCLAW_PREROUTE 2>/dev/null
iptables -t nat -I PREROUTING 1 -j OPENCLAW_PREROUTE

iptables -t nat -D OUTPUT -j OPENCLAW_OUT 2>/dev/null
iptables -t nat -I OUTPUT 1 -j OPENCLAW_OUT

echo "Blocking web traffic until monitor is ready..."

# 1. PERF FAST-PATH: Allow packets for established connections to bypass rule checks
iptables -A OPENCLAW_OUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OPENCLAW_FWD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 2. Allow indispensable traffic (local loopback and DNS)
iptables -A OPENCLAW_OUT -o lo -j ACCEPT
iptables -A OPENCLAW_OUT -p udp --dport 53 -j ACCEPT
iptables -A OPENCLAW_OUT -p tcp --dport 53 -j ACCEPT

# 2. Allow the mitm-proxy user to talk to the internet (Infinite Loop Protector)
PROXY_UID=$(id -u mitm-proxy)
iptables -A OPENCLAW_OUT -m owner --uid-owner $PROXY_UID -j ACCEPT

# Exclude dockerd user (root / UID 0) from proxy interception so image pulls work natively
iptables -t nat -A OPENCLAW_OUT -m owner --uid-owner 0 -j RETURN

# Exclude internal Docker subnets from the proxy redirect (so node can still talk to the gateway/each other natively)
iptables -t nat -A OPENCLAW_OUT -d 10.0.0.0/8 -j RETURN
iptables -t nat -A OPENCLAW_OUT -d 172.16.0.0/12 -j RETURN
iptables -t nat -A OPENCLAW_OUT -d 192.168.0.0/16 -j RETURN

# 3. REDIRECT all other HTTP/HTTPS traffic to the local monitor
iptables -t nat -A OPENCLAW_OUT -p tcp -m owner ! --uid-owner $PROXY_UID --dport 80 -j REDIRECT --to-port 8080
iptables -t nat -A OPENCLAW_OUT -p tcp -m owner ! --uid-owner $PROXY_UID --dport 443 -j REDIRECT --to-port 8080

# Exclude internal Docker subnets from the proxy redirect (so sandboxes can still talk to the gateway/each other natively)
iptables -t nat -A OPENCLAW_PREROUTE -d 10.0.0.0/8 -j RETURN
iptables -t nat -A OPENCLAW_PREROUTE -d 172.16.0.0/12 -j RETURN
iptables -t nat -A OPENCLAW_PREROUTE -d 192.168.0.0/16 -j RETURN

# Also redirect traffic originating from inner Docker containers (sandboxes) to the internet monitor
iptables -t nat -A OPENCLAW_PREROUTE -p tcp --dport 80 -j REDIRECT --to-port 8080
iptables -t nat -A OPENCLAW_PREROUTE -p tcp --dport 443 -j REDIRECT --to-port 8080

# Allow the dockerd user (root / UID 0) to talk to the internet so image pulls work natively
iptables -A OPENCLAW_OUT -m owner --uid-owner 0 -j ACCEPT

# Allow node to communicate natively natively with internal Docker subnets / Host
iptables -A OPENCLAW_OUT -d 10.0.0.0/8 -j ACCEPT
iptables -A OPENCLAW_OUT -d 172.16.0.0/12 -j ACCEPT
iptables -A OPENCLAW_OUT -d 192.168.0.0/16 -j ACCEPT

# Allow internal sandboxes to communicate natively with internal subnets / Host
iptables -A OPENCLAW_FWD -d 10.0.0.0/8 -j ACCEPT
iptables -A OPENCLAW_FWD -d 172.16.0.0/12 -j ACCEPT
iptables -A OPENCLAW_FWD -d 192.168.0.0/16 -j ACCEPT

# 4. STRICT ZERO-TRUST FAIL-CLOSED: Reject EVERYTHING ELSE.
# Drops all external non-HTTP/HTTPS traffic, alternate ports, and raw connections
iptables -A OPENCLAW_OUT -j REJECT
iptables -A OPENCLAW_FWD -j REJECT

# 5. HARDEN CONFIG PERMISSIONS (Defense in Depth)
# We restrict the parent directories so the 'openclaw' user cannot even enter them.
echo "Hardening configuration permissions..."
chown -R predicate:predicate /etc/predicate && chmod 700 /etc/predicate
chown -R mitm-proxy:mitm-proxy /etc/mitmproxy && chmod 750 /etc/mitmproxy

echo "Done. All web traffic is now routed through the local egress guardian."
