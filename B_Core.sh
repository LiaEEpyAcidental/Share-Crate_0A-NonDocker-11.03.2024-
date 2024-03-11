#!/bin/bash

# Monero wallet RPC endpoint
WALLET_RPC_ENDPOINT="http://127.0.0.1:18082/json_rpc"

# Logging function
log_action() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local description="$1"
    local success="$2"
    printf "[%s] %s | Success: %s\n" "$timestamp" "$description" "$success"
}

# Function to get the unlocked balance of the hardcoded address
getUnlockedBalance() {
    echo "Querying unlocked balance from the wallet..."
    local REQUEST_PAYLOAD='{
      "jsonrpc":"2.0",
      "id":"0",
      "method":"get_balance",
      "params": {
        "account_index": 0
      }
    }'
    local RESPONSE=$(curl -s "$WALLET_RPC_ENDPOINT" -d "$REQUEST_PAYLOAD" -H 'Content-Type: application/json')
    if [ $? -eq 0 ]; then
        local UNLOCKED_BALANCE=$(echo $RESPONSE | jq -r '.result.unlocked_balance')
        if [[ "$UNLOCKED_BALANCE" != "null" ]]; then
            # Convert and return the unlocked balance from atomic units to XMR
            local CONVERTED_BALANCE=$(echo "scale=12; $UNLOCKED_BALANCE/1000000000000" | bc)
            echo "Unlocked balance in XMR: $CONVERTED_BALANCE"
            log_action "Queried unlocked balance successfully" "true"
            echo $CONVERTED_BALANCE
        else
            log_action "Failed to query balance" "false"
            return 1
        fi
    else
        log_action "RPC request failed" "false"
        return 1
    fi
}

# Function to send transactions using transfer_split
sendTransactions() {
    local AMOUNT_PER_ADDRESS=$1
    echo "Preparing to send transactions using transfer_split..."
    # Preparing JSON array of destinations
    local DESTINATIONS_JSON="["
    for address in "${addresses[@]}"; do
        DESTINATIONS_JSON+="{\"amount\":$AMOUNT_PER_ADDRESS,\"address\":\"$address\"},"
    done
    # Remove last comma
    DESTINATIONS_JSON="${DESTINATIONS_JSON%,}]"

    local REQUEST_PAYLOAD=$(cat <<EOF
{
    "jsonrpc": "2.0",
    "id": "0",
    "method": "transfer_split",
    "params": {
        "destinations": $DESTINATIONS_JSON,
        "priority": 1,
        "ring_size": 11
    }
}
EOF
)
    local RESPONSE=$(curl -s "$WALLET_RPC_ENDPOINT" -d "$REQUEST_PAYLOAD" -H 'Content-Type: application/json')
    local STATUS=$(echo $RESPONSE | jq -r '.result.status')
    if [[ "$STATUS" == "OK" ]]; then
        echo "Transactions prepared successfully with transfer_split."
        log_action "Prepared transactions with transfer_split" "true"
    else
        echo "Failed to prepare transactions with transfer_split."
        log_action "Failed to prepare transactions with transfer_split" "false"
    fi
}

# Ensure jq and bc are installed
if ! command -v jq &> /dev/null || ! command -v bc &> /dev/null; then
    log_action "jq or bc not installed" "false"
    echo "jq or bc tools are required but not installed."
    exit 1
fi

echo "Reading addresses from stdin..."
# Read addresses into an array from stdin
readarray -t addresses

# Calculate the number of addresses
num_addresses=${#addresses[@]}

if [ "$num_addresses" -eq 0 ]; then
    log_action "No addresses provided" "false"
    exit 1
fi

# Get the total unlocked balance to distribute
TOTAL_AMOUNT_XMR=$(getUnlockedBalance)
TOTAL_AMOUNT_ATOMIC_UNITS=$(echo "$TOTAL_AMOUNT_XMR * 1000000000000" | bc | cut -d'.' -f1) # Convert XMR to atomic units

if [ $? -eq 0 ]; then
    # Calculate the amount each address receives in atomic units
    AMOUNT_PER_ADDRESS=$(echo "$TOTAL_AMOUNT_ATOMIC_UNITS / $num_addresses" | bc)

    echo "Distributing $TOTAL_AMOUNT_XMR XMR among $num_addresses addresses."
    echo "Each address will receive approximately $(echo "scale=12; $AMOUNT_PER_ADDRESS / 1000000000000" | bc) XMR"

    # Send transactions
    sendTransactions $AMOUNT_PER_ADDRESS
else
    log_action "Failed to get total unlocked balance" "false"
fi
