#!/bin/bash

# Configuration Variables

# RPC endpoint: Specify the URL of the node to be monitored.
RPC='http://127.0.0.1:8899'

# VOTE_ACCOUNT: Address of the voting account.
VOTE_ACCOUNT='TJxK9eH3Wq628YtwCgavBMP47VoZ8yx1r2U4fxYgMhqp'

# VALIDATOR_IDENTITY: Address of the validator.
VALIDATOR_IDENTITY='MxL3TbQ6Jk035NsaRpeoZHK21RmF9yt4e7V8ljVcPzsd'

# exporter_home_path: Directory path for storing all exporter files and subfolders.
# Ensure that this directory is owned by the user managing the node-exporter process
# and that it has the necessary permissions for recursive access.
exporter_home_path="/opt/solana-exporter"

# metrics_prefix: Prefix for metrics, used in Prometheus and Grafana for identifying metrics.
# It's formatted as 'solana_<metric_name>'.
# Do not modify this if you are using the provided Grafana json dashboard, otherwise make your own.
metrics_prefix='solana'

# log_level: Controls the verbosity of log output.
# Set to "debug" for detailed logs "or anything also" for standard logging.
log_level="info"

# execution_timeout: Maximum allowable time in seconds for the script to complete.
# If the script does not finish within this time, it will terminate all operations.
# This setting should be less than the interval set in the cron job.
# For example, if the cron job timeout is 60 seconds, consider setting this to 30 seconds
# to ensure proper script execution.
execution_timeout=46 # 46 should be good for once per minute cron

# End of configuration <===========================================================================

# Lock file configuration
lock_file="${exporter_home_path}/exporter.lock"

# Check for existing lock file to ensure only one instance runs at a time
if [ -f "$lock_file" ]; then
    log_message "ERRO: Another instance is already running, we can not process !" "$log_file_path"
    exit 0
fi

# Create a lock file
if ! touch "$lock_file" 2>/dev/null; then
    log_message "ERROR: Failed to create lock file. Check permissions." "$log_file_path"
    exit 1
fi

# Setup cleanup function to remove lock file on script exit
cleanup() {
    rm -f "$lock_file"
    log_message "Lock file removed" "$log_file_path"
}
trap cleanup EXIT

# Define directories and exports
temp_files="${exporter_home_path}/tmp"
prometheus_files="${exporter_home_path}/files"
functions_storage_path="${exporter_home_path}/functions"
log_file_path="${exporter_home_path}/solana_exporter.log"
rpc_responses_prom_file="${temp_files}/rpc_responses.prom"

# Ensure variables can be used globaly across external functions
export temp_files prometheus_files functions_storage_path log_file_path rpc_responses_prom_file metrics_prefix log_level

# Source scripts
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

# shellcheck disable=SC1090
for script in "${scripts[@]}"; do
    script_path="${functions_storage_path}/${script}.fn"
    if [[ -f "$script_path" ]]; then
        source "$script_path"
    else
        log_message "ERROR: Missing file ${script_path}" "$log_file_path"
        exit 1
    fi
done

check_dependency # check if all files and folders in place and we have access

log_message '==> Starting Solana metrics collection <==' "$log_file_path"

# Grab timestamp for execution time calculation
start_time=$(date +%s%N) # capture time in nanoseconds

# Health status <================= metrics collection starts here
health_status=$(getHealth "${RPC}")
create_prom_file "validator_health" "Validator health status" "gauge" "${health_status}"

# Account information
account_info=$(get_account_info "$RPC" "$VOTE_ACCOUNT")
metrics=( "$account_info" )
create_multiple_prom_files "${metrics[@]}"

# Epoch progress
epoch_progress=$(get_epoch_progress "$RPC")
create_prom_file "epoch_progress" "Epoch progress in percentage" "gauge" "$epoch_progress"

# Current slot
current_slot=$(get_current_slot "$RPC")
create_prom_file "current_slot" "Current slot" "gauge" "$current_slot"

# Assigned leader slots in this ongoing epoch
assigned_slots=$(get_assigned_slots "$RPC" "$VALIDATOR_IDENTITY")
create_prom_file "epoch_slots_assigned_total" "Slots assigned to the validator" "gauge" "$assigned_slots"

# Max retransmit slot
max_retransmit_slot=$(get_max_retransmit_slot "$RPC")
create_prom_file "max_retransmit_slot" "Maximum retransmit slot number" "gauge" "$max_retransmit_slot"

# Max shred insert slot
max_shred_insert_slot=$(get_max_shred_insert_slot "$RPC")
create_prom_file "max_shred_insert_slot" "Maximum shred insert slot number" "gauge" "$max_shred_insert_slot"

# Highest snapshot slot
metrics_output=$(get_highest_snapshot_slot "$RPC")
metrics_array=( "$metrics_output" )
create_multiple_prom_files "${metrics_array[@]}"

# Block production metrics
block_production_metrics=$(get_block_production "$RPC" "$VALIDATOR_IDENTITY")
block_production_array=( "$block_production_metrics" )
create_multiple_prom_files "${block_production_array[@]}"

# Version information
version_info=$(getVersion "$RPC")
version_array=( "$version_info" )
create_multiple_prom_files "${version_array[@]}"

# Balances
validator_identity_balance=$(getBalance "$VALIDATOR_IDENTITY" "$RPC")
create_prom_file "validator_identity_account_balance" "Identity account balance $VALIDATOR_IDENTITY" "gauge" "$validator_identity_balance"

# Metrics collection done, we expect all RPC calls to complete here <====================================================================

# End timing and calculate duration in nanoseconds for all RPC calls in total
end_time=$(date +%s%N)
duration=$((end_time - start_time))

duration_sec=$(echo "scale=3; $duration / 1000000000" | bc | awk '{printf "%.3f\n", $0}') # Convert nanoseconds to sconds for logging

# Check if execution time exceeds the threshold before cleanup
if [ "$((duration / 1000000000))" -ge "$execution_timeout" ]; then
    log_message "ERRO: Execution time exceeding threshold, exiting !!!" "$log_file_path"
    exit 1
fi

log_message "==> All RPC calls completed in: ${duration_sec} second(s) <==" "$log_file_path"

create_prom_file "exporter_execution_time" "RPC calls processing time total in nanoseconds" "gauge" "$duration"

# Node-exporter handling
atomic_swap_prom_files
