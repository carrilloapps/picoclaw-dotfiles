#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# workflow.sh -- Multi-step agent workflows with state and resumption
# =============================================================================
# Lightweight workflow engine for chaining agent tasks. Each step can depend
# on previous output. State is persisted so workflows can be resumed.
#
# Workflow format (JSON or YAML):
#   {
#     "name": "daily-briefing",
#     "steps": [
#       {"id": "weather", "prompt": "Get the weather for Madrid"},
#       {"id": "news", "prompt": "Summarize top 3 tech news stories"},
#       {"id": "combine", "prompt": "Combine ${weather} and ${news} into a briefing",
#        "depends_on": ["weather", "news"]}
#     ]
#   }
#
# Usage:
#   ~/bin/workflow.sh run <workflow.json>              # Execute workflow
#   ~/bin/workflow.sh status <run-id>                  # Show state of a run
#   ~/bin/workflow.sh list                             # List all runs
#   ~/bin/workflow.sh resume <run-id>                  # Resume failed/paused run
#   ~/bin/workflow.sh new <name>                       # Create empty template
# =============================================================================

set -eu
WF_DIR="${HOME}/.picoclaw/workflows"
RUN_DIR="${HOME}/.picoclaw/workflow-runs"
mkdir -p "$WF_DIR" "$RUN_DIR"

run_workflow() {
    local wf_file="$1"
    local run_id="run_$(date +%s)_$$"
    local run_dir="$RUN_DIR/$run_id"
    mkdir -p "$run_dir"
    cp "$wf_file" "$run_dir/workflow.json"
    echo "{\"status\":\"running\",\"started\":\"$(date -Iseconds)\",\"outputs\":{}}" > "$run_dir/state.json"

    echo "Run: $run_id"
    local steps_count
    steps_count=$(jq '.steps | length' "$wf_file")

    for i in $(seq 0 $((steps_count - 1))); do
        local step_id prompt depends
        step_id=$(jq -r ".steps[$i].id" "$wf_file")
        prompt=$(jq -r ".steps[$i].prompt" "$wf_file")
        depends=$(jq -r ".steps[$i].depends_on // [] | join(\" \")" "$wf_file")

        # Substitute \${step_id} with previous outputs
        for dep in $depends; do
            local dep_output
            dep_output=$(jq -r ".outputs[\"$dep\"] // \"\"" "$run_dir/state.json")
            prompt=$(echo "$prompt" | sed "s|\${$dep}|$dep_output|g")
        done

        echo "  [$((i+1))/$steps_count] $step_id"
        local output
        output=$(echo "$prompt" | SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem "$HOME/picoclaw.bin" agent -s "cli:wf-$run_id-$step_id" 2>&1 | tail -20 | grep -v '^\[' | grep -v 'Goodbye')

        # Store output (escape for JSON)
        local esc_output
        esc_output=$(echo "$output" | jq -Rs .)
        jq ".outputs[\"$step_id\"] = $esc_output" "$run_dir/state.json" > "$run_dir/state.tmp" && mv "$run_dir/state.tmp" "$run_dir/state.json"
    done

    jq ".status = \"completed\" | .ended = \"$(date -Iseconds)\"" "$run_dir/state.json" > "$run_dir/state.tmp" && mv "$run_dir/state.tmp" "$run_dir/state.json"
    echo "Completed: $run_id"
    echo "Outputs:"
    jq '.outputs' "$run_dir/state.json"
}

case "${1:-help}" in
    run)
        WF="${2:?}"
        [ -f "$WF" ] || { echo "Workflow file not found: $WF"; exit 1; }
        run_workflow "$WF"
        ;;
    status)
        ID="${2:?}"
        [ -d "$RUN_DIR/$ID" ] || { echo "Run not found"; exit 1; }
        jq . "$RUN_DIR/$ID/state.json"
        ;;
    list)
        ls -1t "$RUN_DIR" 2>/dev/null | head -20 | while read -r id; do
            status=$(jq -r .status "$RUN_DIR/$id/state.json" 2>/dev/null || echo '?')
            echo "$id  [$status]"
        done
        ;;
    resume)
        echo "Resume not yet implemented. Use: run"
        ;;
    new)
        NAME="${2:?}"
        cat > "$WF_DIR/$NAME.json" << 'EOF'
{
  "name": "example",
  "description": "Example workflow with 2 steps",
  "steps": [
    {"id": "step1", "prompt": "Give me a 1-line fact about the current time."},
    {"id": "step2", "prompt": "Write a haiku about: ${step1}", "depends_on": ["step1"]}
  ]
}
EOF
        echo "Created: $WF_DIR/$NAME.json"
        ;;
    help|*)
        head -25 "$0" | tail -23 | sed 's/^# //;s/^#//'
        ;;
esac
