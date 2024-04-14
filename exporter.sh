#!/bin/bash

# Run this from cron in whatever prefered interval
# * * * * * /bin/bash -c 'cd /opt/solana-exporter && ./exporter.sh'

# Configuration Variables
RPC='127.0.0.1:1234'

VOTE_ACCOUNT='vote-account-address'         # vote account address
VALIDATOR_IDENTITY='identity-address'       # identity address
exporter_home_path="/opt/solana-exporter"   # exporter home dir

metrics_prefix='solana'

# ---------------------------------------

temp_files="${exporter_home_path}/tmp"
prometheus_files="${exporter_home_path}/files"
functions_storage_path="${exporter_home_path}/functions"
log_file_path="${exporter_home_path}/solana_exporter.log"
rpc_responses_prom_file="${temp_files}/rpc_responses.prom"

# export so they can be userd widely across external functions
export temp_files="${temp_files}"
export prometheus_files="${prometheus_files}"
export functions_storage_path="${functions_storage_path}"
export log_file_path="${log_file_path}"
export rpc_responses_prom_file="${rpc_responses_prom_file}"
export metrics_prefix="${metrics_prefix}"

# Source all functions from the functions list
scripts=(
    log
    check_dependency
    atomic_swap
    metrics-constructor
    json_validator
    health
    credits
    epoch-progress
    current_slot
    get_assigned_slots
    getMaxRetransmitSlot
    getMaxShredInsertSlot
    get_highest_snapshot_slot
    get_block_production
    get_version
    getBalance
)

for script in "${scripts[@]}"; do
    source "${functions_storage_path}/${script}.fn"
done

check_dependency # check if all files and folders in place

# Logging function initialization
echo "$(date "+%Y-%m-%d %H:%M:%S") - Starting Solana metrics collection" >> "$log_file_path"

# Health status
health_status=$(getHealth "${RPC}")
create_prom_file "validator_health" "Validator health status" "gauge" "${health_status}"

# Account information
account_info=$(get_account_info "$RPC" "$VOTE_ACCOUNT")
metrics=( $account_info )
create_multiple_prom_files "${metrics[@]}"

# Epoch progress
epoch_progress=$(get_epoch_progress "$RPC")
create_prom_file "epoch_progress" "Epoch progress in percentage" "gauge" "$epoch_progress"

# Current slot
current_slot=$(get_current_slot "$RPC")
create_prom_file "current_slot" "Current slot" "gauge" "$current_slot"

# Assigned slots
assigned_slots=$(get_assigned_slots "$RPC" "$VALIDATOR_IDENTITY")
create_prom_file "assigned_slots" "Slots assigned to the validator" "gauge" "$assigned_slots"

# Max retransmit slot
max_retransmit_slot=$(get_max_retransmit_slot "$RPC")
create_prom_file "max_retransmit_slot" "Maximum retransmit slot number" "gauge" "$max_retransmit_slot"

# Max shred insert slot
max_shred_insert_slot=$(get_max_shred_insert_slot "$RPC")
create_prom_file "max_shred_insert_slot" "Maximum shred insert slot number" "gauge" "$max_shred_insert_slot"

# Highest snapshot slot
metrics_output=$(get_highest_snapshot_slot "$RPC")
metrics_array=( $metrics_output )
create_multiple_prom_files "${metrics_array[@]}"

# Block production metrics
block_production_metrics=$(get_block_production "$RPC" "$VALIDATOR_IDENTITY")
block_production_array=( $block_production_metrics )
create_multiple_prom_files "${block_production_array[@]}"

# Version information
version_info=$(getVersion "$RPC")
version_array=( $version_info )
create_multiple_prom_files "${version_array[@]}"

# Balances
validator_identity_balance=$(getBalance "$VALIDATOR_IDENTITY" "$RPC")
create_prom_file "validator_identity_account_balance" "Identity account balance $VALIDATOR_IDENTITY" "gauge" "$validator_identity_balance"


# Symlink instead of write
atomic_swap_prom_files
