#!/bin/bash

# ddev-generated
## Description: [BASE] Shows CI pipeline status
## Usage: ci-pipeline-status
## Example: "ddev cps"
## Aliases: ci-pipe-status, cps

config_file="/var/www/ddev-ci/config.yml"

function validateConfigFile() {
    if [[ ! -s "$config_file" ]]; then
        echo "Configuration file $config_file does not exist or is empty."
        exit 1
    fi
}

function fetchGitRemoteUrl() {
    git config --get remote.origin.url
}

function extractGitDomain() {
    local url="$1"
    if [[ "$url" == git@* ]]; then
        echo "$url" | sed -E 's|git@([^:]+):.*|\1|'
    elif [[ "$url" == https://* ]]; then
        echo "$url" | sed -E 's|https://([^/]+)/.*|\1|'
    else
        echo "Unsupported URL format: $url"
        exit 1
    fi
}

function extractGitProjectPath() {
    local url="$1"
    if [[ "$url" == git@* ]]; then
        echo "$url" | sed -E 's|git@[^:]+:(.*)\.git|\1|'
    elif [[ "$url" == https://* ]]; then
        echo "$url" | sed -E 's|https://[^/]+/(.*)\.git|\1|'
    else
        echo "Unsupported URL format: $url"
        exit 1
    fi
}

function retrievePrivateToken() {
    local domain="$1"
    local token=$(yq -r ".hosts.\"$domain\".token" "$config_file")
    if [[ -z "$token" ]]; then
        echo "PRIVATE_TOKEN is not set or is empty."
        exit 1
    fi
    echo "$token"
}

function fetchGitLabApiUrl() {
    local domain="$1"
    local url=$(yq -r ".hosts.\"$domain\".api_host" "$config_file")
    if [[ -z "$url" ]]; then
        echo "API host for $domain is not set or is empty."
        exit 1
    fi
    echo "https://$url"
}

function encodeProjectPath() {
    local path="$1"
    echo -n "$path" | jq -sRr @uri
}

function queryProjectDetails() {
    local apiUrl="$1"
    local token="$2"
    curl -s --header "PRIVATE-TOKEN: $token" "$apiUrl"
}

function extractProjectId() {
    local details="$1"
    echo "$details" | jq '.id'
}

function queryPipelineDetails() {
    local apiUrl="$1"
    local token="$2"
    curl -s --header "PRIVATE-TOKEN: $token" "$apiUrl"
}

function displayPipelineInfo() {
    local details="$1"
    local url="$2"
    echo "PIPELINE INFO:"
    echo " - ID: $(echo "$details" | jq '.id')"
    echo " - Status: $(echo "$details" | jq '.status')"
    echo " - Created: $(echo "$details" | jq '.created_at')"
    echo " - URL: $url"
}

function showJobProgress() {
    local jobs="$1"
    declare -A stages
    declare -a stage_order

    while IFS= read -r job; do
        local job_name=$(echo "$job" | jq -r '.name')
        local job_status=$(echo "$job" | jq -r '.status')
        local job_stage=$(echo "$job" | jq -r '.stage')
        local job_duration=$(echo "$job" | jq -r '.duration // 0 | floor')

        if [[ -z "${stages[$job_stage]}" ]]; then
            stage_order+=("$job_stage")
        fi

        case $job_status in
            "success") color=$(tput setaf 2) ;; # green
            "running") color=$(tput setaf 5) ;; # magenta
            "failed") color=$(tput setaf 1) ;;  # red
            "created") color=$(tput setaf 3) ;; # yellow
            "pending") color=$(tput setaf 4) ;; # blue
            "waiting_for_resource") continue ;;
            *) color=$(tput sgr0) ;; # reset
        esac

        stages[$job_stage]+="${color} - ${job_name}: ${job_status} - ${job_duration}s$(tput sgr0)\n"
    done < <(echo "$jobs" | jq -c '.[]')

    for ((i=${#stage_order[@]}-1; i>=0; i--)); do
        stage="${stage_order[i]}"
        echo " Stage: $stage"
        echo -e "${stages[$stage]}"
    done
}

function main() {
    validateConfigFile
    git_remote_url=$(fetchGitRemoteUrl)
    domain=$(extractGitDomain "$git_remote_url")
    project_path=$(extractGitProjectPath "$git_remote_url")
    private_token=$(retrievePrivateToken "$domain")
    gitlab_api_url=$(fetchGitLabApiUrl "$domain")
    gitlab_api="$gitlab_api_url/api/v4"
    encoded_project_path=$(encodeProjectPath "$project_path")
    project_details=$(queryProjectDetails "$gitlab_api/projects/$encoded_project_path" "$private_token")
    project_id=$(extractProjectId "$project_details")

    if [[ -z "$project_id" || "$project_id" == "null" ]]; then
        echo "project_id is not set or is empty."
        exit 1
    fi

    tput civis
    project_details=$(queryProjectDetails "$gitlab_api/projects/$project_id" "$private_token")
    namespace=$(echo "$project_details" | jq -r '.namespace.full_path')
    project_name=$(echo "$project_details" | jq -r '.path')
    tput clear
    echo "PROJECT: $project_name"
    echo

    pipeline=$(queryPipelineDetails "$gitlab_api/projects/$project_id/pipelines?status=running" "$private_token" | jq '.[0]')
    if [[ "$pipeline" == "null" ]]; then
        echo "No running pipelines."
        tput cnorm
        exit 0
    fi

    pipeline_id=$(echo "$pipeline" | jq '.id')
    pipeline_details=$(queryPipelineDetails "$gitlab_api/projects/$project_id/pipelines/$pipeline_id" "$private_token")
    displayPipelineInfo "$pipeline_details" "$gitlab_api_url/$namespace/$project_name/-/pipelines/$(echo "$pipeline_details" | jq -r '.id')"

    while true; do
        tput cup 8 0
        echo "PIPELINE PROGRESS:"
        jobs=$(queryPipelineDetails "$gitlab_api/projects/$project_id/pipelines/$pipeline_id/jobs" "$private_token")
        showJobProgress "$jobs"

         pipeline_details=$(queryPipelineDetails "$gitlab_api/projects/$project_id/pipelines/$pipeline_id" "$private_token")
         pipeline_status=$(echo $pipeline_details | jq -r '.status')

         running_jobs=$(echo "$jobs" | jq -r '.[] | select(.status == "running")')

         if [[ -z "$running_jobs" && "$pipeline_status" != "running" && "$pipeline_status" != "pending" && "$pipeline_status" != "created" && "$pipeline_status" != "waiting_for_resource" ]]; then
             echo
             echo "Pipeline finished with status: $pipeline_status"
             break
         fi

        sleep 2
    done

    finished_at=$(echo "$pipeline_details" | jq -r '.finished_at')
    created_at=$(echo "$pipeline_details" | jq -r '.created_at')

    if [[ "$finished_at" != "null" && "$created_at" != "null" ]]; then
      duration=$(($(date -d "$finished_at" +%s) - $(date -d "$created_at" +%s)))
      echo "Total pipeline time: ${duration}s"
    else
      echo "Total pipeline time: not available"
    fi

    tput cnorm
}

main
