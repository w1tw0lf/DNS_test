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

# Global arrays to store test results
declare -a DNS_IPV4_RESULTS
declare -a DNS_IPV6_RESULTS
declare -a DOT_IPV4_RESULTS
declare -a DOT_IPV6_RESULTS
declare -a DOH_IPV4_RESULTS
declare -a DOH_IPV6_RESULTS
declare -a PING_IPV4_RESULTS
declare -a PING_IPV6_RESULTS



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

    # Perform IPv4 DNS query if applicable using the default public server
    if [[ "$TEST_MODE" == "both" || "$TEST_MODE" == "ipv4_only" ]]; then
        while read -r line; do
            DNS_IPV4_RESULTS+=("$line")
        done < <(dig +short A "$domain" @"$DEFAULT_DNS_SERVER_IPV4")
    fi

    # Perform IPv6 DNS query if applicable using the default public server
    if [[ "$TEST_MODE" == "both" || "$TEST_MODE" == "ipv6_only" ]]; then
        while read -r line; do
            DNS_IPV6_RESULTS+=("$line")
        done < <(dig +short AAAA "$domain" @"$DEFAULT_DNS_SERVER_IPV6")
    fi
}

# Function to perform DNS over TLS (DoT) test
perform_dot_test() {
    local domain=$1

    # Using default public DoT servers
    if [[ "$TEST_MODE" == "both" || "$TEST_MODE" == "ipv4_only" ]]; then
        while read -r line; do
            DOT_IPV4_RESULTS+=("$line")
        done < <(dig +short A "$domain" @"$DEFAULT_DOT_SERVER_IPV4")
    fi

    if [[ "$TEST_MODE" == "both" || "$TEST_MODE" == "ipv6_only" ]]; then
        while read -r line; do
            DOT_IPV6_RESULTS+=("$line")
        done < <(dig +short AAAA "$domain" @"$DEFAULT_DOT_SERVER_IPV6")
    fi
}

# Function to perform DNS over HTTPS (DoH) test
perform_doh_test() {
    local domain=$1

    # Using default public DoH server
    local doh_server="$DEFAULT_DOH_SERVER"

    if [[ "$TEST_MODE" == "both" || "$TEST_MODE" == "ipv4_only" ]]; then
        while read -r line; do
            local type=$(echo "$line" | awk '{print $4}')
            local ttl=$(echo "$line" | awk '{print $2}')
            local address=$(echo "$line" | awk '{print $5}')
            DOH_IPV4_RESULTS+=("$type,$ttl,$address")
        done < <(dig @"$doh_server" +https "$domain" A +noall +answer)
    fi

     if [[ "$TEST_MODE" == "both" || "$TEST_MODE" == "ipv6_only" ]]; then
         while read -r line; do
             local type=$(echo "$line" | awk '{print $4}')
             local ttl=$(echo "$line" | awk '{print $2}')
             local address=$(echo "$line" | awk '{print $5}')
             DOH_IPV6_RESULTS+=("$type,$ttl,$address")
         done < <(dig @"$doh_server" +https "$domain" AAAA +noall +answer)
     fi
}


# Function to perform Ping test
perform_ping_test() {
    local domain=$1

    # Perform IPv4 ping if applicable
    if [[ "$TEST_MODE" == "both" || "$TEST_MODE" == "ipv4_only" ]]; then
        local ping_output_ipv4=$(ping -c 4 -W 1 "$domain" 2>&1)
        while read -r time; do
            PING_IPV4_RESULTS+=("$time")
        done < <(echo "$ping_output_ipv4" | grep " time=" | sed 's/.*time=\([0-9\.]*\).*/\1/' | head -n 4)
    fi

    # Perform IPv6 ping if applicable
    if [[ "$TEST_MODE" == "both" || "$TEST_MODE" == "ipv6_only" ]]; then
        local ping_output_ipv6=$(ping -6 -c 4 -W 1 "$domain" 2>&1)
        while read -r time; do
            PING_IPV6_RESULTS+=("$time")
        done < <(echo "$ping_output_ipv6" | grep " time=" | sed 's/.*time=\([0-9\.]*\).*/\1/' | head -n 4)
    fi
}

# Function to print the summary table
print_summary_table() {
    local max_test_type_len=$(echo -n "Test Type" | wc -c)
    local max_protocol_len=$(echo -n "Protocol" | wc -c)
    local max_result_len=$(echo -n "Result" | wc -c)

    # Calculate max lengths for DNS results
    for result in "${DNS_IPV4_RESULTS[@]}"; do
        if (( $(echo -n "DNS" | wc -c) > max_test_type_len )); then max_test_type_len=$(echo -n "DNS" | wc -c); fi
        if (( $(echo -n "IPv4" | wc -c) > max_protocol_len )); then max_protocol_len=$(echo -n "IPv4" | wc -c); fi
        if (( $(echo -n "$result" | wc -c) > max_result_len )); then max_result_len=$(echo -n "$result" | wc -c); fi
    done
    for result in "${DNS_IPV6_RESULTS[@]}"; do
        if (( $(echo -n "DNS" | wc -c) > max_test_type_len )); then max_test_type_len=$(echo -n "DNS" | wc -c); fi
        if (( $(echo -n "IPv6" | wc -c) > max_protocol_len )); then max_protocol_len=$(echo -n "IPv6" | wc -c); fi
        if (( $(echo -n "$result" | wc -c) > max_result_len )); then max_result_len=$(echo -n "$result" | wc -c); fi
    done

    # Calculate max lengths for DoT results
    for result in "${DOT_IPV4_RESULTS[@]}"; do
        if (( $(echo -n "DoT" | wc -c) > max_test_type_len )); then max_test_type_len=$(echo -n "DoT" | wc -c); fi
        if (( $(echo -n "IPv4" | wc -c) > max_protocol_len )); then max_protocol_len=$(echo -n "IPv4" | wc -c); fi
        if (( $(echo -n "$result" | wc -c) > max_result_len )); then max_result_len=$(echo -n "$result" | wc -c); fi
    done
    for result in "${DOT_IPV6_RESULTS[@]}"; do
        if (( $(echo -n "DoT" | wc -c) > max_test_type_len )); then max_test_type_len=$(echo -n "DoT" | wc -c); fi
        if (( $(echo -n "IPv6" | wc -c) > max_protocol_len )); then max_protocol_len=$(echo -n "IPv6" | wc -c); fi
        if (( $(echo -n "$result" | wc -c) > max_result_len )); then max_result_len=$(echo -n "$result" | wc -c); fi
    done

    # Calculate max lengths for DoH results
    for result in "${DOH_IPV4_RESULTS[@]}"; do
        IFS=',' read -r type ttl address <<< "$result"
        if (( $(echo -n "DoH" | wc -c) > max_test_type_len )); then max_test_type_len=$(echo -n "DoH" | wc -c); fi
        if (( $(echo -n "IPv4 ($type, TTL: $ttl)" | wc -c) > max_protocol_len )); then max_protocol_len=$(echo -n "IPv4 ($type, TTL: $ttl)" | wc -c); fi
        if (( $(echo -n "$address" | wc -c) > max_result_len )); then max_result_len=$(echo -n "$address" | wc -c); fi
    done
    for result in "${DOH_IPV6_RESULTS[@]}"; do
        IFS=',' read -r type ttl address <<< "$result"
        if (( $(echo -n "DoH" | wc -c) > max_test_type_len )); then max_test_type_len=$(echo -n "DoH" | wc -c); fi
        if (( $(echo -n "IPv6 ($type, TTL: $ttl)" | wc -c) > max_protocol_len )); then max_protocol_len=$(echo -n "IPv6 ($type, TTL: $ttl)" | wc -c); fi
        if (( $(echo -n "$address" | wc -c) > max_result_len )); then max_result_len=$(echo -n "$address" | wc -c); fi
    done

    # Calculate max lengths for Ping results
    local ipv4_ping_avg="N/A"
    if (( ${#PING_IPV4_RESULTS[@]} > 0 )); then
        local sum=0
        for time_val in "${PING_IPV4_RESULTS[@]}"; do
            sum=$(echo "$sum + $time_val" | bc)
        done
        ipv4_ping_avg="$(echo "scale=2; $sum / ${#PING_IPV4_RESULTS[@]}" | bc) ms"
    fi
    if (( $(echo -n "Ping" | wc -c) > max_test_type_len )); then max_test_type_len=$(echo -n "Ping" | wc -c); fi
    if (( $(echo -n "IPv4" | wc -c) > max_protocol_len )); then max_protocol_len=$(echo -n "IPv4" | wc -c); fi
    if (( $(echo -n "$ipv4_ping_avg" | wc -c) > max_result_len )); then max_result_len=$(echo -n "$ipv4_ping_avg" | wc -c); fi

    local ipv6_ping_avg="N/A"
    if (( ${#PING_IPV6_RESULTS[@]} > 0 )); then
        local sum=0
        for time_val in "${PING_IPV6_RESULTS[@]}"; do
            sum=$(echo "$sum + $time_val" | bc)
        done
        ipv6_ping_avg="$(echo "scale=2; $sum / ${#PING_IPV6_RESULTS[@]}" | bc) ms"
    fi
    if (( $(echo -n "Ping" | wc -c) > max_test_type_len )); then max_test_type_len=$(echo -n "Ping" | wc -c); fi
    if (( $(echo -n "IPv6" | wc -c) > max_protocol_len )); then max_protocol_len=$(echo -n "IPv6" | wc -c); fi
    if (( $(echo -n "$ipv6_ping_avg" | wc -c) > max_result_len )); then max_result_len=$(echo -n "$ipv6_ping_avg" | wc -c); fi

    echo "# DNS Test Results"
    echo ""

    # Print header
    printf "|%s|%s|%s|
" "$(printf '%0.s-' $(seq 1 $((max_test_type_len + 2))))" "$(printf '%0.s-' $(seq 1 $((max_protocol_len + 2))))" "$(printf '%0.s-' $(seq 1 $((max_result_len + 2))))"
    printf "| %-*s | %-*s | %-*s |
" "$max_test_type_len" "Test Type" "$max_protocol_len" "Protocol" "$max_result_len" "Result"
    printf "|%s|%s|%s|
" "$(printf '%0.s-' $(seq 1 $((max_test_type_len + 2))))" "$(printf '%0.s-' $(seq 1 $((max_protocol_len + 2))))" "$(printf '%0.s-' $(seq 1 $((max_result_len + 2)))))"

    # DNS Results
    for result in "${DNS_IPV4_RESULTS[@]}"; do
        printf "| %-*s | %-*s | %-*s |
" "$max_test_type_len" "DNS" "$max_protocol_len" "IPv4" "$max_result_len" "$result"
    done
    for result in "${DNS_IPV6_RESULTS[@]}"; do
        printf "| %-*s | %-*s | %-*s |
" "$max_test_type_len" "DNS" "$max_protocol_len" "IPv6" "$max_result_len" "$result"
    done

    # DoT Results
    for result in "${DOT_IPV4_RESULTS[@]}"; do
        printf "| %-*s | %-*s | %-*s |
" "$max_test_type_len" "DoT" "$max_protocol_len" "IPv4" "$max_result_len" "$result"
    done
    for result in "${DOT_IPV6_RESULTS[@]}"; do
        printf "| %-*s | %-*s | %-*s |
" "$max_test_type_len" "DoT" "$max_protocol_len" "IPv6" "$max_result_len" "$result"
    done

    # DoH Results
    for result in "${DOH_IPV4_RESULTS[@]}"; do
        IFS=',' read -r type ttl address <<< "$result"
        printf "| %-*s | %-*s | %-*s |
" "$max_test_type_len" "DoH" "$max_protocol_len" "IPv4 ($type, TTL: $ttl)" "$max_result_len" "$address"
    done
    for result in "${DOH_IPV6_RESULTS[@]}"; do
        IFS=',' read -r type ttl address <<< "$result"
        printf "| %-*s | %-*s | %-*s |
" "$max_test_type_len" "DoH" "$max_protocol_len" "IPv6 ($type, TTL: $ttl)" "$max_result_len" "$address"
    done

    # Ping Results
    printf "| %-*s | %-*s | %-*s |
" "$max_test_type_len" "Ping" "$max_protocol_len" "IPv4" "$max_result_len" "$ipv4_ping_avg"
    printf "| %-*s | %-*s | %-*s |
" "$max_test_type_len" "Ping" "$max_protocol_len" "IPv6" "$max_result_len" "$ipv6_ping_avg"
    printf "|%s|%s|%s|
" "$(printf -- '-%.0s' $(seq 1 $((max_test_type_len + 2))))" "$(printf -- '-%.0s' $(seq 1 $((max_protocol_len + 2))))" "$(printf -- '-%.0s' $(seq 1 $((max_result_len + 2))))"
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

print_summary_table
