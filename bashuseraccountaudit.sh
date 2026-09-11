#!/usr/bin/env bash
set -u

OUTPUT_DIRECTORY="${1:-$(pwd)}"
mkdir -p "$OUTPUT_DIRECTORY" 2>/dev/null || {
  echo "Unable to create output directory: $OUTPUT_DIRECTORY" >&2
  exit 1
}

timestamp=$(date +"%Y%m%dT%H%M%S")
csv_path="$OUTPUT_DIRECTORY/user_audit_${timestamp}.csv"
json_path="$OUTPUT_DIRECTORY/user_audit_${timestamp}.json"
json_tmp="$(mktemp)"

cleanup() {
  rm -f "$json_tmp"
}
trap cleanup EXIT

csv_escape() {
  local value="${1-}"
  value=${value//$'\r'/ }
  value=${value//$'\n'/ }

  if [[ "$value" == *,* || "$value" == *'"'* ]]; then
    value=${value//\"/\"\"}
    printf '"%s"' "$value"
  else
    printf '%s' "$value"
  fi
}

json_escape() {
  local value="${1-}"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

is_admin_for_user() {
  local user_name="$1"
  local group
  local groups

  groups=$(id -nG "$user_name" 2>/dev/null || true)
  for group in $groups; do
    case "$group" in
      root|sudo|wheel|adm|Administrators)
        return 0
        ;;
    esac
  done

  return 1
}

get_account_state() {
  local user_name="$1"
  local password_status

  if ! command -v passwd >/dev/null 2>&1; then
    printf '%s' 'Active'
    return 0
  fi

  password_status=$(passwd -S "$user_name" 2>/dev/null | awk '{print $2}')
  case "$password_status" in
    L|LK)
      printf '%s' 'Locked'
      ;;
    NP)
      printf '%s' 'NoPassword'
      ;;
    *)
      printf '%s' 'Active'
      ;;
  esac
}

get_password_required() {
  local state="$1"
  if [[ "$state" == "NoPassword" ]]; then
    printf '%s' 'No'
  else
    printf '%s' 'Yes'
  fi
}

get_chage_value() {
  local user_name="$1"
  local label="$2"
  local output

  if ! command -v chage >/dev/null 2>&1; then
    printf '%s' 'Not available'
    return 0
  fi

  output=$(chage -l "$user_name" 2>/dev/null || true)
  if [[ -z "$output" ]]; then
    printf '%s' 'Not available'
    return 0
  fi

  while IFS= read -r line; do
    case "$line" in
      "$label"*)
        printf '%s' "${line#*: }"
        return 0
        ;;
    esac
  done <<< "$output"

  printf '%s' 'Not available'
}

printf '%s\n' 'UserName,FullName,IsAdmin,AccountActive,PasswordRequired,PasswordExpires,PasswordLastSet,LastLogon,Comment,Groups,Flags' > "$csv_path"
printf '%s\n' '[' > "$json_path"
first_record=true

while IFS=: read -r user_name _ _ _ gecos _; do
  [[ -n "$user_name" ]] || continue

  full_name="${gecos%%,*}"
  comment="$gecos"
  groups=$(id -nG "$user_name" 2>/dev/null || true)
  groups_csv="${groups// /; }"

  account_state="$(get_account_state "$user_name")"
  is_admin=false
  if is_admin_for_user "$user_name"; then
    is_admin=true
  fi

  password_required="$(get_password_required "$account_state")"
  password_expires="$(get_chage_value "$user_name" 'Password expires')"
  password_last_set="$(get_chage_value "$user_name" 'Last password change')"
  last_logon='Not available'
  flags=''
  if [[ "$account_state" == 'Locked' ]]; then
    flags='AccountDisabled'
  fi

  csv_row="$(printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s' \
    "$(csv_escape "$user_name")" \
    "$(csv_escape "$full_name")" \
    "$(csv_escape "$is_admin")" \
    "$(csv_escape "$account_state")" \
    "$(csv_escape "$password_required")" \
    "$(csv_escape "$password_expires")" \
    "$(csv_escape "$password_last_set")" \
    "$(csv_escape "$last_logon")" \
    "$(csv_escape "$comment")" \
    "$(csv_escape "$groups_csv")" \
    "$(csv_escape "$flags")")"
  printf '%s\n' "$csv_row" >> "$csv_path"

  if [[ "$first_record" == true ]]; then
    first_record=false
  else
    printf ',\n' >> "$json_path"
  fi

  printf '  {"UserName":"%s","FullName":"%s","IsAdmin":%s,"AccountActive":"%s","PasswordRequired":"%s","PasswordExpires":"%s","PasswordLastSet":"%s","LastLogon":"%s","Comment":"%s","Groups":"%s","Flags":"%s"}' \
    "$(json_escape "$user_name")" \
    "$(json_escape "$full_name")" \
    "$is_admin" \
    "$(json_escape "$account_state")" \
    "$(json_escape "$password_required")" \
    "$(json_escape "$password_expires")" \
    "$(json_escape "$password_last_set")" \
    "$(json_escape "$last_logon")" \
    "$(json_escape "$comment")" \
    "$(json_escape "$groups_csv")" \
    "$(json_escape "$flags")" >> "$json_path"
done < <(getent passwd 2>/dev/null || cat /etc/passwd 2>/dev/null)

printf '\n]\n' >> "$json_path"

echo "User audit complete."
echo "CSV: $csv_path"
echo "JSON: $json_path"
