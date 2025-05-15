#!/bin/bash

# This script checks for IPv4 and IPv6 connectivity and then performs
# DNS, DoT, DoH, and ping tests for a specified domain.
# Dependencies: dig, ping, ping -6, curl, jq

# --- Default Public DNS Servers for Tests ---
# Used for initial connectivity check and standard DNS test
DEFAULT_DNS_SERVER_IPV4=$(dig $domain+noall +stats | awk '/SERVER:/ {sub(/#.*/, "", $3); print $3}' | tr -d '\n')
DEFAULT_DNS_SERVER_IPV6=$(dig $domain+noall +stats | awk '/SERVER:/ {sub(/#.*/, "", $3); print $3}' | tr -d '\n')

# Used for DoT test
DEFAULT_DOT_SERVER_IPV4=$(dig $domain+noall +stats | awk '/SERVER:/ {sub(/#.*/, "", $3); print $3}' | tr -d '\n')
DEFAULT_DOT_SERVER_IPV6=$(dig $domain+noall +stats | awk '/SERVER:/ {sub(/#.*/, "", $3); print $3}' | tr -d '\n')

# Used for DoH test (hostname for dig +https)
DEFAULT_DOH_SERVER=($(dig SVCB _dns.resolver.arpa +short | awk 'NF && /^1 / {sub(/\.$/, "", $2); print $2}'))
# -------------------------------------------


# Function to check IPv4/IPv6 connectivity
check_connectivity() {
    echo "Checking IPv4 and IPv6 connectivity..."

    # Use dig to check for A (IPv4) and AAAA (IPv6) records for a reliable domain
    # Using default public DNS servers for the check to determine general connectivity
    ipv4_status=$(dig +short A google.com @"$DEFAULT_DNS_SERVER_IPV4")
    ipv6_status=$(dig +short AAAA google.com @"$DEFAULT_DNS_SERVER_IPV6")

    has_ipv4=false
    has_ipv6=false

    # Check if dig returned any results for IPv4
    if [[ -n "$ipv4_status" ]]; then
        has_ipv4=true
    fi

    # Check if dig returned any results for IPv6
    if [[ -n "$ipv6_status" ]]; then
        has_ipv6=true
    fi

    echo "" # Add a newline for cleaner output

    if $has_ipv4 && $has_ipv6; then
        echo "Both local machine and WAN support IPv4 and IPv6."
        echo "Testing both IPv4 and IPv6..."
        TEST_MODE="both"
    elif $has_ipv4; then
        echo "Only IPv4 connectivity detected."
        echo "Testing IPv4 only..."
        TEST_MODE="ipv4_only"
    elif $has_ipv6; then
         echo "Only IPv6 connectivity detected."
         echo "Testing IPv6 only..."
         TEST_MODE="ipv6_only"
    else
        echo "No IPv4 or IPv6 connectivity detected. Cannot perform tests."
        TEST_MODE="none"
    fi
    echo "" # Add a newline
}

# Function to perform standard DNS test
perform_dns_test() {
    local domain=$1
    echo "--- DNS test ---"
    echo ""

    # Markdown table header
    echo "| Address |"


    # Perform IPv4 DNS query if applicable using the default public server
    if [[ "$TEST_MODE" == "both" || "$TEST_MODE" == "ipv4_only" ]]; then
        echo "IPv4 addresses (via $DEFAULT_DNS_SERVER_IPV4):"
        # Use dig +short to get only the answer records
        dig +short A "$domain" @"$DEFAULT_DNS_SERVER_IPV4" | while read -r line; do
            echo "| $line |"
        done
    fi

    # Perform IPv6 DNS query if applicable using the default public server
    if [[ "$TEST_MODE" == "both" || "$TEST_MODE" == "ipv6_only" ]]; then
        echo "IPv6 addresses (via $DEFAULT_DNS_SERVER_IPV6):"
        dig +short AAAA "$domain" @"$DEFAULT_DNS_SERVER_IPV6" | while read -r line; do
             echo "| $line |"
         done
    fi
    echo "" # Add a newline
}

# Function to perform DNS over TLS (DoT) test
perform_dot_test() {
    local domain=$1
    echo "--- DOT test ---"
    echo ""

    # Markdown table header
    echo "| Address |"

    # Using default public DoT servers
    if [[ "$TEST_MODE" == "both" || "$TEST_MODE" == "ipv4_only" ]]; then
        echo "IPv4 addresses (via DoT: $DEFAULT_DOT_SERVER_IPV4):"
        # Check if the DoT server is reachable on port 853
 #       timeout 5 bash -c "echo >/dev/tcp/$DEFAULT_DOT_SERVER_IPV4/853" 2>/dev/null && echo "| $DEFAULT_DOT_SERVER_IPV4 (DoT server reachable) |" || echo "| $DEFAULT_DOT_SERVER_IPV4 (DoT server not reachable) |"
        # Attempt to query via DoT
        dig +short A "$domain" @"$DEFAULT_DOT_SERVER_IPV4" | while read -r line; do
             echo "| $line |"
         done
    fi

    if [[ "$TEST_MODE" == "both" || "$TEST_MODE" == "ipv6_only" ]]; then
        echo "IPv6 addresses (via DoT: $DEFAULT_DOT_SERVER_IPV6):"
        # Check if the IPv6 DoT server is reachable on port 853
  #      timeout 5 bash -c "echo >/dev/tcp/[$DEFAULT_DOT_SERVER_IPV6]/853" 2>/dev/null && echo "| $DEFAULT_DOT_SERVER_IPV6 (DoT server reachable) |" || echo "| $DEFAULT_DOT_SERVER_IPV6 (DoT server not reachable) |"
        # Attempt to query via DoT
        dig +short AAAA "$domain" @"$DEFAULT_DOT_SERVER_IPV6" | while read -r line; do
             echo "| $line |"
         done
    fi
    echo "" # Add a newline
}

# Function to perform DNS over HTTPS (DoH) test
perform_doh_test() {
    local domain=$1
    echo "--- DOH test ---"
    echo ""

    # Markdown table header
    echo "| Type | TTL | Address |"

    # Using default public DoH server
    local doh_server="$DEFAULT_DOH_SERVER"

    if [[ "$TEST_MODE" == "both" || "$TEST_MODE" == "ipv4_only" ]]; then
        echo "IPv4 results (via DoH: $doh_server):"
        # Use dig +https to query the DoH endpoint
        dig @"$doh_server" +https "$domain" A +noall +answer | while read -r line; do
            # Parse the dig output to extract Type, TTL, and Address
            # Example line: domain.com.        60      IN      A       1.2.3.4
            local type=$(echo "$line" | awk '{print $4}')
            local ttl=$(echo "$line" | awk '{print $2}')
            local address=$(echo "$line" | awk '{print $5}')
            echo "| $type | $ttl | $address |"
        done
    fi

     if [[ "$TEST_MODE" == "both" || "$TEST_MODE" == "ipv6_only" ]]; then
         echo "IPv6 results (via DoH: $doh_server):"
         dig @"$doh_server" +https "$domain" AAAA +noall +answer | while read -r line; do
             # Parse the dig output to extract Type, TTL, and Address
             # Example line: domain.com.        60      IN      AAAA       2001:db8::1
             local type=$(echo "$line" | awk '{print $4}')
             local ttl=$(echo "$line" | awk '{print $2}')
             local address=$(echo "$line" | awk '{print $5}')
             echo "| $type | $ttl | $address |"
         done
     fi
    echo "" # Add a newline
}


# Function to perform Ping test
perform_ping_test() {
    local domain=$1
    echo "--- Ping test ---"
    echo ""

    # Markdown table header
    echo "| IPv4 | IPv6 |"
    echo "|---|---| "

    local ipv4_pings=()
    local ipv6_pings=()

    # Perform IPv4 ping if applicable
    if [[ "$TEST_MODE" == "both" || "$TEST_MODE" == "ipv4_only" ]]; then
        echo "Pinging IPv4..."
        # Ping 4 times, wait 1 second for response (-W 1), extract time
        local ping_output_ipv4=$(ping -c 4 -W 1 "$domain" 2>&1)
        echo "--- Raw IPv4 Ping Output ---"
        echo "$ping_output_ipv4"
        echo "----------------------------"
        echo "$ping_output_ipv4" | grep " time=" | sed 's/.*time=\([0-9\.]*\).*/\1/' | head -n 4 | while read -r time; do
            echo "Captured IPv4 time: $time" # Debugging line
            ipv4_pings+=("$time ms")
        done
    fi

    # Perform IPv6 ping if applicable
    if [[ "$TEST_MODE" == "both" || "$TEST_MODE" == "ipv6_only" ]]; then
        echo "Pinging IPv6..."
        # ping -6 4 times, wait 1 second for response (-W 1), extract time
        local ping_output_ipv6=$(ping -6 -c 4 -W 1 "$domain" 2>&1)
        echo "--- Raw IPv6 Ping Output ---"
        echo "$ping_output_ipv6"
        echo "----------------------------"
        echo "$ping_output_ipv6" | grep " time=" | sed 's/.*time=\([0-9\.]*\).*/\1/' | head -n 4 | while read -r time; do
            echo "Captured IPv6 time: $time" # Debugging line
            ipv6_pings+=("$time ms")
        done
    fi

    # Print ping results side-by-side in the table format
    local max_pings=${#ipv4_pings[@]}
    if (( ${#ipv6_pings[@]} > max_pings )); then
        max_pings=${#ipv6_pings[@]}
    fi

    # Loop through the results and print them row by row
    for i in $(seq 0 $((max_pings - 1))); do
        local ipv4_res="${ipv4_pings[$i]:-N/A}" # Use N/A if no result for this index
        local ipv6_res="${ipv6_pings[$i]:-N/A}" # Use N/A if no result for this index
        echo "| $ipv4_res | $ipv6_res |"
    done
    echo "" # Add a newline
}


# --- Main script execution ---

echo "DNS Test Script"
echo "==============="
echo "" # Add a newline

# Check connectivity first
check_connectivity

# Exit if no connectivity was detected
if [[ "$TEST_MODE" == "none" ]]; then
    exit 1
fi

# Prompt the user for the domain to test
read -p "Enter the domain (e.g. google.com): " domain
echo "" # Add a newline

# Perform the tests based on the detected connectivity mode
if [[ "$TEST_MODE" == "both" || "$TEST_MODE" == "ipv4_only" || "$TEST_MODE" == "ipv6_only" ]]; then
    perform_doh_test "$domain"
    perform_dot_test "$domain"
    perform_dns_test "$domain"
    perform_ping_test "$domain"
fi

echo "Tests complete."
