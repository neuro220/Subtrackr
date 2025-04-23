#!/bin/bash

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Global Variables
VERBOSE=false
RETRIES=2
output_dir=""
temp_dir=""
DOMAIN=""

# Display Banner
show_banner() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo " ██████╗ ██╗   ██╗██████╗ ███████╗██████╗ ██████╗  ██████╗ "
    echo "██╔═══██╗██║   ██║██╔══██╗██╔════╝██╔══██╗██╔══██╗██╔═══██╗"
    echo "██║   ██║██║   ██║██║  ██║█████╗  ██║  ██║██████╔╝██║   ██║"
    echo "██║▄▄ ██║██║   ██║██║  ██║██╔══╝  ██║  ██║██╔══██╗██║   ██║"
    echo "╚██████╔╝╚██████╔╝██████╔╝███████╗██████╔╝██║  ██║╚██████╔╝"
    echo " ╚══▀▀═╝  ╚═════╝ ╚═════╝ ╚══════╝╚═════╝ ╚═╝  ╚═╝ ╚═════╝ "
    echo -e "${NC}"
    echo -e "${YELLOW}Subdomain Enumeration Toolkit${NC}"
}

# Animated progress indicator
spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# User input with style
ask_user() {
    echo -e "${BOLD}${GREEN}🚀 Enter target domain: ${NC}\c"
    read DOMAIN
    echo -e "${BOLD}${GREEN}📁 Output directory (default: current dir): ${NC}\c"
    read -e output_dir
    output_dir=${output_dir:-$(pwd)}
    temp_dir="$output_dir/tmp_$RANDOM"

    mkdir -p "$temp_dir" || {
        echo -e "${RED}❌ Failed to create directories!${NC}"
        exit 1
    }
}

# Verbose output handler
verbose() {
    if $VERBOSE; then
        echo -e "${YELLOW}[VERBOSE] $@${NC}"
    fi
}

# Retry function
with_retry() {
    local command="$@"
    local attempt=0

    while [ $attempt -le $RETRIES ]; do
        if $VERBOSE; then
            $command
        else
            $command >/dev/null 2>&1
        fi

        if [ $? -eq 0 ]; then
            return 0
        fi

        ((attempt++))
        if [ $attempt -le $RETRIES ]; then
            echo -e "${YELLOW}⚠️ Retrying ($attempt/$RETRIES)...${NC}"
            sleep 2
        fi
    done

    echo -e "${RED}❌ Command failed after $RETRIES attempts${NC}"
    return 1
}

# Tool Functions
run_subfinder() {
    echo -e "\n${BOLD}${BLUE}[🔎 Subfinder Scan]${NC}"
    with_retry subfinder -d "$DOMAIN" -all -o "$temp_dir/domain1.txt"
}

run_sublist3r() {
    echo -e "\n${BOLD}${BLUE}[🔍 Sublist3r Scan]${NC}"
    with_retry sublist3r -d "$DOMAIN" -o "$temp_dir/domain2.txt"
}

run_assetfinder() {
    echo -e "\n${BOLD}${BLUE}[📦 Assetfinder Scan]${NC}"
    with_retry assetfinder --subs-only "$DOMAIN" > "$temp_dir/domain3.txt"
}

export GITHUB_TOKEN="GITHUB_TOKEN"  # Replace with your actual token
run_github_subdomains() {
    echo -e "\n${BOLD}${BLUE}[🐙 GitHub Subdomains Scan]${NC}"
    if [ -z "$GITHUB_TOKEN" ]; then
        echo -e "${RED}❌ GitHub token not found! Set GITHUB_TOKEN environment variable${NC}"
        return 1
    fi
    with_retry github-subdomains -d "$DOMAIN" -t "$GITHUB_TOKEN" -o "$temp_dir/domain4.txt"
}

run_otx() {
    echo -e "\n${BOLD}${BLUE}[👽 OTX AlienVault Scan]${NC}"
    with_retry curl -s "https://otx.alienvault.com/api/v1/indicators/domain/$DOMAIN/url_list?limit=100&page=1" | \
    grep -o '"hostname": *"[^"]*' | \
    sed 's/"hostname": "//' | \
    sort -u > "$temp_dir/domain5.txt"
}

run_subdomain_center() {
    echo -e "\n${BOLD}${BLUE}[🌐 Subdomain Center Scan]${NC}"
    with_retry curl -s "https://api.subdomain.center/?domain=$DOMAIN" | \
    jq -r '.[]' | \
    sort -u > "$temp_dir/domain6.txt"
}

# Dependency Check
check_dependencies() {
    local dependencies=("subfinder" "sublist3r" "assetfinder" "github-subdomains" "curl" "jq")
    local missing=()

    for cmd in "${dependencies[@]}"; do
        if ! command -v $cmd &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}❌ Missing dependencies:"
        printf ' - %s\n' "${missing[@]}"
        echo -e "${NC}"
        exit 1
    fi
}

# Main Execution
show_banner
check_dependencies
ask_user

echo -e "\n${BOLD}${CYAN}💡 Starting scan for ${DOMAIN}...${NC}"

# Run all scan functions
{
    run_subfinder &
    spinner
    run_sublist3r &
    spinner
    run_assetfinder &
    spinner
    run_github_subdomains &
    spinner
    run_otx &
    spinner
    run_subdomain_center &
    spinner
} | tee -a "$output_dir/scan.log"

# Combine results
echo -e "\n${BOLD}${CYAN}🔗 Combining results...${NC}"
cat "$temp_dir"/domain*.txt | sort -u > "$output_dir/main.txt"

# Final Output
echo -e "\n${BOLD}${GREEN}✅ Scan completed! Results saved to:"
echo -e "📂 ${output_dir}/main.txt${NC}"
echo -e "${BOLD}💡 Found $(wc -l < "$output_dir/main.txt") subdomains${NC}"

# Cleanup
rm -rf "$temp_dir"