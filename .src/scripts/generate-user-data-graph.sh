#!/bin/bash
# Generate Mermaid graph markdown for the current Pensieve user data root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

usage() {
    cat <<'USAGE'
Usage:
  generate-user-data-graph.sh [--root <path>] [--output <path>]

Options:
  --root <path>      Scan root. Default: current user data root
  --output <path>    Output markdown file. Default: stdout
  -h, --help         Show this help
USAGE
}

ROOT=""
OUTPUT="-"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)
            [[ $# -ge 2 ]] || { echo "Missing value for --root" >&2; exit 1; }
            ROOT="$2"
            shift 2
            ;;
        --output)
            [[ $# -ge 2 ]] || { echo "Missing value for --output" >&2; exit 1; }
            OUTPUT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

PROJECT_ROOT="$(project_root)"
if [[ -z "$ROOT" ]]; then
    ROOT="$(user_data_root)"
fi
ROOT="$(to_posix_path "$ROOT")"

if [[ ! -d "$ROOT" ]]; then
    echo "Scan root does not exist: $ROOT" >&2
    exit 1
fi

if [[ "$OUTPUT" != "-" ]]; then
    OUTPUT="$(to_posix_path "$OUTPUT")"
    if [[ "$OUTPUT" != /* ]]; then
        OUTPUT="$PROJECT_ROOT/$OUTPUT"
    fi
    mkdir -p "$(dirname "$OUTPUT")"
fi

# Build a stable file list without relying on GNU-only flags (e.g., sort -z).
files=()
while IFS= read -r file; do
    files+=("$file")
done < <(find "$ROOT" -type f -name '*.md' | LC_ALL=C sort)

# Compute TTL cutoff date for short-term items (today - 7 days)
TTL_CUTOFF="$(date -u -v-7d +"%Y-%m-%d" 2>/dev/null || date -u -d "7 days ago" +"%Y-%m-%d" 2>/dev/null || echo "")"

run_awk() {
awk \
    -v root="$ROOT" \
    -v output="$OUTPUT" \
    -v ttl_cutoff="$TTL_CUTOFF" '
function trim(s) {
    sub(/^[[:space:]]+/, "", s)
    sub(/[[:space:]]+$/, "", s)
    return s
}
function relpath(path, r) {
    if (index(path, r "/") == 1) return substr(path, length(r) + 2)
    if (path == r) return ""
    return path
}
function strip_short_term(rel) {
    if (index(rel, "short-term/") == 1) return substr(rel, 12)
    return rel
}
function category(rel, arr, n, stripped) {
    stripped = strip_short_term(rel)
    n = split(stripped, arr, "/")
    if (n <= 1) return "root"
    return arr[1]
}
function allowed(cat) {
    return (cat == "root" || cat == "maxims" || cat == "decisions" || cat == "knowledge" || cat == "pipelines")
}
function basename_noext(path, arr, n) {
    n = split(path, arr, "/")
    return arr[n]
}
function add_member(cat, rel, key) {
    key = cat SUBSEP rel
    if (!(key in member_seen)) {
        member_seen[key] = 1
        member_list[cat] = member_list[cat] rel "\n"
        node_count++
        node_order[node_count] = rel
        node_cat[rel] = cat
    }
}
function is_generated_graph(rel) {
    if (rel ~ /^graph(\.[^\/]+)?\.md$/) return 1
    if (rel ~ /^_pensieve-graph(\.[^\/]+)?\.md$/) return 1
    if (rel ~ /^pensieve-graph(\.[^\/]+)?\.md$/) return 1
    return 0
}
BEGIN {
    node_count = 0
    edge_count = 0
    cats[1] = "root";      cat_title["root"] = "Root"
    cats[2] = "maxims";    cat_title["maxims"] = "Maxims"
    cats[3] = "decisions"; cat_title["decisions"] = "Decisions"
    cats[4] = "knowledge"; cat_title["knowledge"] = "Knowledge"
    cats[5] = "pipelines"; cat_title["pipelines"] = "Pipelines"
}
{
    if (FNR == 1) {
        file_allowed = 0
        st_pending = 0
        st_in_fm = 0
        if (FILENAME == output) {
            next
        }
        current_rel = relpath(FILENAME, root)
        if (is_generated_graph(current_rel)) {
            next
        }
        # For short-term files, defer add_member until we check TTL
        if (index(current_rel, "short-term/") == 1) {
            current_rel = strip_short_term(current_rel)
            current_cat = category(current_rel)
            if (allowed(current_cat)) {
                st_pending = 1
                st_in_fm = 1
                file_allowed = 1
            }
        } else {
            current_cat = category(current_rel)
            if (allowed(current_cat)) {
                add_member(current_cat, current_rel)
                file_allowed = 1
            }
        }
    }
    # For short-term files: parse frontmatter to check created date
    if (st_pending) {
        if (FNR == 1 && $0 ~ /^---/) { next }
        if ($0 ~ /^---/) {
            # End of frontmatter reached without finding created — include anyway
            st_pending = 0
            add_member(current_cat, current_rel)
            next
        }
        if ($0 ~ /^created:[[:space:]]/) {
            sub(/^created:[[:space:]]*/, "", $0)
            sub(/[[:space:]].*$/, "", $0)
            if (ttl_cutoff != "" && $0 != "" && $0 <= ttl_cutoff) {
                # Expired: exclude from graph
                file_allowed = 0
            } else {
                add_member(current_cat, current_rel)
            }
            st_pending = 0
            next
        }
    }
    if (!file_allowed) next

    line = $0
    label = "link"
    if (index(line, "基于") > 0 || index(line, "based-on") > 0) label = "based-on"
    else if (index(line, "导致") > 0 || index(line, "leads-to") > 0) label = "leads-to"
    else if (index(line, "相关") > 0 || index(line, "related") > 0) label = "related"

    s = line
    while (match(s, /\[\[[^][]+\]\]/)) {
        tok = substr(s, RSTART + 2, RLENGTH - 4)
        sub(/\|.*/, "", tok)
        sub(/#.*/, "", tok)
        tok = trim(tok)
        if (tok != "") {
            edge_count++
            edge_from[edge_count] = current_rel
            edge_to_raw[edge_count] = tok
            edge_label[edge_count] = label
        }
        s = substr(s, RSTART + RLENGTH)
    }
}
END {
    for (i = 1; i <= node_count; i++) {
        rel = node_order[i]
        ids[rel] = "n" i

        rel_noext = rel
        sub(/\.md$/, "", rel_noext)
        noext_map[rel_noext] = rel

        base = basename_noext(rel_noext)
        base_count[base]++
        if (base_count[base] == 1) base_map[base] = rel
        else base_map[base] = ""
    }

    print "<!-- AUTO-GENERATED FILE. DO NOT EDIT MANUALLY. -->"
    print "<!-- Generated by: .src/scripts/generate-user-data-graph.sh -->"
    print ""
    print "# Pensieve User Data Graph"
    print ""
    print "> Auto-generated in Claude Code; in other environments, run `bash \"$PENSIEVE_SKILL_ROOT/.src/scripts/maintain-project-state.sh\" --event sync` after editing pensieve to trigger generation."
    print ""
    print "- Root: `" root "`"
    print "- Categories: maxims, decisions, knowledge, pipelines"
    print ""
    print "```mermaid"
    print "graph LR"

    for (ci = 1; ci <= 5; ci++) {
        cat = cats[ci]
        if (!(cat in member_list) || member_list[cat] == "") continue

        print "  subgraph \"" cat_title[cat] "\""
        n = split(member_list[cat], members, "\n")
        for (j = 1; j <= n; j++) {
            rel = members[j]
            if (rel == "") continue
            label_txt = rel
            gsub(/"/, "\\\"", label_txt)
            print "    " ids[rel] "[\"" label_txt "\"]"
        }
        print "  end"
    }

    resolved = 0
    unresolved = 0
    for (i = 1; i <= edge_count; i++) {
        src = edge_from[i]
        tok = edge_to_raw[i]
        lbl = edge_label[i]

        if (!(src in ids)) continue

        t = tok
        if (index(t, ".claude/skills/pensieve/") == 1) t = substr(t, 25)
        else if (index(t, ".claude/pensieve/") == 1) t = substr(t, 18)
        if (substr(t, 1, 1) == "/") t = substr(t, 2)
        sub(/\.md$/, "", t)

        tgt = ""
        if (t in noext_map) tgt = noext_map[t]
        else if (index(t, "/") == 0 && base_count[t] == 1) tgt = base_map[t]

        if (tgt != "" && (tgt in ids)) {
            edge_key = src SUBSEP lbl SUBSEP tgt
            if (!(edge_key in edge_seen)) {
                edge_seen[edge_key] = 1
                edge_unique_count++
                edge_unique_src[edge_unique_count] = src
                edge_unique_tgt[edge_unique_count] = tgt
                edge_unique_lbl[edge_unique_count] = lbl
            }
        } else {
            unresolved_key = src SUBSEP tok
            if (!(unresolved_key in unresolved_seen)) {
                unresolved_seen[unresolved_key] = 1
                unresolved++
                unresolved_src[unresolved] = src
                unresolved_tok[unresolved] = tok
            }
        }
    }

    # Simplify inverse semantic duplicates:
    #   A --based-on--> B and B --leads-to--> A keep only "based-on".
    for (i = 1; i <= edge_unique_count; i++) {
        keep_edge[i] = 1
        if (edge_unique_lbl[i] == "leads-to") {
            reverse_based_key = edge_unique_tgt[i] SUBSEP "based-on" SUBSEP edge_unique_src[i]
            if (reverse_based_key in edge_seen) keep_edge[i] = 0
        }
    }
    for (i = 1; i <= edge_unique_count; i++) {
        if (!keep_edge[i]) continue
        src = edge_unique_src[i]
        tgt = edge_unique_tgt[i]
        lbl = edge_unique_lbl[i]
        if (lbl == "link") print "  " ids[src] " --> " ids[tgt]
        else print "  " ids[src] " -->|" lbl "| " ids[tgt]
        resolved++
    }

    print "```"
    print ""
    print "### Summary"
    print ""
    print "- Notes scanned: " node_count
    print "- Links found: " edge_count
    print "- Links resolved: " resolved
    print "- Links unresolved: " unresolved

    if (unresolved > 0) {
        print ""
        print "### Unresolved Links"
        print ""
        for (i = 1; i <= unresolved; i++) {
            print "- `" unresolved_src[i] "` -> `[[" unresolved_tok[i] "]]`"
        }
    }
}
' "$@"
}

if [[ "$OUTPUT" == "-" ]]; then
    if [[ ${#files[@]} -eq 0 ]]; then
        run_awk < /dev/null
    else
        run_awk "${files[@]}"
    fi
else
    if [[ ${#files[@]} -eq 0 ]]; then
        run_awk < /dev/null > "$OUTPUT"
    else
        run_awk "${files[@]}" > "$OUTPUT"
    fi
    echo "✅ Graph generated: $OUTPUT"
fi
