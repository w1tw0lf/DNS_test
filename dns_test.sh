#!/bin/bash

clear
echo " ____  _   _ ____    _____         _    "
echo "|  _ \| \ | / ___|  |_   _|__  ___| |_  "
echo "| | | |  \| \___ \    | |/ _ \/ __| __| "
echo "| |_| | |\  |___) |   | |  __/\__ \ |_  "
echo "|____/|_| \_|____/    |_|\___||___/\__| "
echo "                                        "
echo "----------------------------------------------------- "

echo ""

ipv6_local_status=$(ip -6 addr show)
ipv6_wan_status=$(curl -6 -s -I www.google.com)
if [ -n "$ipv6_local_status" ] && [ -n "$ipv6_wan_status" ]; then
    echo "Both local machine and WAN support IPv6. Testing both IPv4 and IPv6..."
    while true; do
        read -p "Enter the domain (e.g. google.com): " domain

        if [[ $domain =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            if nslookup $domain >/dev/null 2>&1; then
                echo ""
                break
            else
                echo "Domain $domain is valid but does not exist. Please enter a valid domain."
            fi
        else
            echo "Invalid domain. Please enter a valid domain."
        fi
    done

    doh_server=($(dig SVCB _dns.resolver.arpa +short | awk -F'1' '{print $2}' | awk -F'. ' '{print $1}'))
    if [ -n "$doh_server" ]; then
        echo "DOH test...."
        doh4="curl -s -H 'accept: application/dns-json' 'https://$doh_server/dns-query?name=$domain&type=A'"
        doh4_output=$(eval "$doh4")
        echo "$doh4_output" >doh4_output

        doh6="curl -s -H 'accept: application/dns-json' 'https://$doh_server/dns-query?name=$domain&type=AAAA'"
        doh6_output=$(eval "$doh6")
        echo "$doh6_output" >doh6_output

        echo "DOT test...."
        dig +tls "$domain" +short > dot
        dig +tls "$domain" AAAA +short > dot6
    else
        echo "No DOH server available"
        doh4_output='{"Answer":[{"name":"N/A","type":"N/A","TTL":"N/A","data":"N/A"}]}'
        echo "$doh4_output" >doh4_output

        doh6_output='{"Answer":[{"name":"N/A","type":"N/A","TTL":"N/A","data":"N/A"}]}'
        echo "$doh6_output" >doh6_output

        echo "No DOT server available"
        echo "N/A" > dot
        echo "N/A" > dot6
    fi

    echo "DNS test...."
    ns_command="nslookup $domain"
    ns_output=$(eval "$ns_command")
    echo "$ns_output" >ns_output

    echo "Ping test...."
    json_file="ping_results.json"
    result1=($(ping -c 4 -4 $domain | grep from))
    result2=($(ping -c 4 -6 $domain | grep from))
    formatted_results=()
    for ((i = 0; i < ${#result1[@]}; i += 9)); do
        formatted_results+=("${result1[i+7]} ${result1[i+8]}")
    done
    for ((i = 0; i < ${#result2[@]}; i += 9)); do
        formatted_results+=("${result2[i+7]} ${result2[i+8]}")
    done
    json_data="{ \"results\": ["
    for line in "${formatted_results[@]}"; do
        json_data="${json_data} \"$line\","
    done
    json_data="${json_data%,} ]}"
    echo $json_data > $json_file

    echo ""
    python3 dns_test.py
    rm doh4_output doh6_output ns_output ping_results.json dot dot6
else
    echo "IPv6 checks failed. Testing IPv4 only..."
    while true; do
        read -p "Enter the domain (e.g. google.com): " domain

        if [[ $domain =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            if nslookup $domain >/dev/null 2>&1; then
                echo ""
                break
            else
                echo "Domain $domain is valid but does not exist. Please enter a valid domain."
            fi
        else
            echo "Invalid domain. Please enter a valid domain."
        fi
    done

    doh_server=($(dig SVCB _dns.resolver.arpa +short | awk -F'1' '{print $2}' | awk -F'. ' '{print $1}'))

    if [ -n "$doh_server" ]; then
        echo "DOH test...."
        doh4="curl -s -H 'accept: application/dns-json' 'https://$doh_server/dns-query?name=$domain&type=A'"
        doh4_output=$(eval "$doh4")
        echo "$doh4_output" >doh4_output

        doh6_output='{"Answer":[{"name":"N/A","type":"N/A","TTL":"N/A","data":"N/A"}]}'
        echo "$doh6_output" >doh6_output

        echo "DOT test...."
        dig +tls "$domain" +short > dot
        echo "N/A" > dot6
    else
        echo "No DOH server available"
        doh4_output='{"Answer":[{"name":"N/A","type":"N/A","TTL":"N/A","data":"N/A"}]}'
        echo "$doh4_output" >doh4_output

        doh6_output='{"Answer":[{"name":"N/A","type":"N/A","TTL":"N/A","data":"N/A"}]}'
        echo "$doh6_output" >doh6_output

        echo "No DOT server available"
        echo "N/A" > dot
        echo "N/A" > dot6
    fi


    echo "DNS test...."
    ns_command="nslookup $domain"
    ns_output=$(eval "$ns_command")
    echo "$ns_output" >ns_output

    echo "Ping test...."
    json_file="ping_results.json"
    result1=($(ping -c 4 -4 $domain | grep from))
    formatted_results=()
    for ((i = 0; i < ${#result1[@]}; i += 9)); do
        formatted_results+=("${result1[i+7]} ${result1[i+8]}")
    done

    json_data="{ \"results\": ["
    for line in "${formatted_results[@]}"; do
        json_data="${json_data} \"$line\","
    done
    json_data="${json_data%,} ]}"
    echo $json_data > $json_file

    echo ""
    python3 dns_test.py
    rm doh4_output doh6_output ns_output ping_results.json dot dot6
fi