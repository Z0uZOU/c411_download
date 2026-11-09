#!/bin/bash

#######################
## Generating script variables and basics
script_name=$(basename "$0" | cut -d'.' -f1)
script_name_cap=${script_name^^}
script_name_full=$(basename "$0")
script_bin="$0"
script_conf="$HOME/.config/$script_name/$script_name.conf"
script_remote="https://raw.githubusercontent.com/Z0uZOU/$script_name/main/$script_name_full"
url_conf_remote="https://raw.githubusercontent.com/Z0uZOU/$script_name/main/url.conf"
script_folder="$HOME/.config/$script_name"
script_tmp_folder="$script_folder/tmp"
script_cron_log="$script_folder/cron.log"
script_db_movies_log="$script_folder/db_movies.log"
script_db_series_log="$script_folder/db_series.log"

#######################
## Local multilingual UI
mui_folder="$script_folder/MUI"
mui_remote_base="https://raw.githubusercontent.com/Z0uZOU/$script_name/main/MUI"
display_language=""
show_cron_log=0
previous_arg=""
for argument in "$@"; do
  if [[ "$previous_arg" == "-l" || "$previous_arg" == "--language" ]]; then
    display_language="$argument"
    previous_arg=""
    continue
  fi
  case "$argument" in
    -l|--language) previous_arg="$argument" ;;
    --language=*) display_language="${argument#*=}" ;;
    -l?*) display_language="${argument#-l}" ;;
    -c|--cron-log) show_cron_log=1 ;;
  esac
done
if [[ -z "$display_language" ]]; then
  display_language="${LANG:-en}"
fi
display_language="${display_language%%.*}"
display_language="${display_language%%_*}"
display_language="${display_language,,}"
[[ "$display_language" =~ ^[a-z][a-z0-9-]*$ ]] || display_language="en"

download-language-file() {
  local language="$1" destination temporary_file

  destination="$mui_folder/$language.lang"
  [[ -r "$destination" ]] && return 0
  mkdir -p "$mui_folder" || return 1
  temporary_file=$(mktemp "$mui_folder/.${language}.lang.XXXXXX") || return 1

  if command -v curl >/dev/null 2>&1; then
    curl --silent --fail --location \
      --connect-timeout 3 --max-time 10 \
      --output "$temporary_file" "$mui_remote_base/$language.lang"
  elif command -v wget >/dev/null 2>&1; then
    wget --quiet --timeout=10 \
      --output-document="$temporary_file" "$mui_remote_base/$language.lang"
  else
    rm -f "$temporary_file"
    return 1
  fi

  if [[ $? -eq 0 && -s "$temporary_file" ]] && bash -n "$temporary_file" 2>/dev/null; then
    chmod 600 "$temporary_file"
    mv -f "$temporary_file" "$destination"
    return 0
  fi

  rm -f "$temporary_file"
  return 1
}

if ! download-language-file "$display_language"; then
  display_language="en"
  download-language-file "$display_language" || true
fi
declare -A MUI=()
if [[ -r "$mui_folder/$display_language.lang" ]]; then
  source "$mui_folder/$display_language.lang"
fi
msg() {
  local key="$1"
  shift
  printf -- "${MUI[$key]:-$key}" "$@"
}
media-name() {
  if [[ "$1" == "series" ]]; then
    msg media_series_singular
  else
    msg media_movie
  fi
}

# Reading the cron log must remain available while the main process holds its lock.
if (( show_cron_log )); then
  echo -e "\033[1m$(msg cron_log_title "$script_name_cap")\033[0m"
  echo
  if [[ -f "$script_cron_log" ]]; then
    date_log=$(date -r "$script_cron_log")
    cat "$script_cron_log"
    echo
    echo "$(msg log_created "$date_log")"
  else
    echo "$(msg no_log)"
  fi
  exit 0
fi

mkdir -p "$script_folder/logs" "$script_folder/torrents" "$script_tmp_folder"
touch "$script_db_movies_log" "$script_db_series_log"
chmod 600 "$script_db_movies_log" "$script_db_series_log"


#######################
## Check if this script is running
lock_file="$script_tmp_folder/$script_name.lock"
exec 200>"$lock_file"

if ! flock -n 200; then
    echo "$(msg already_running)"
    exit 1
fi

#######################
## Advanced command arguments
die() { echo "$*" >&2; exit 2; }
needs_arg() { if [ -z "$OPTARG" ]; then die "$(msg missing_option_arg "$OPT")"; fi; }
needs_long_arg() {
  if [[ -z "$OPTARG" ]] && (( OPTIND <= $# )); then
    OPTARG="${!OPTIND}"
    ((OPTIND++))
  fi
  needs_arg
}

update_config_list() {
  local action="$1"
  local requested_value="$2"
  local setting_name="$3"
  local current_value="$4"
  local config_value line item item_trimmed
  local setting_pattern="^[[:space:]]*${setting_name}[[:space:]]*=(.*)$"
  local value_found=0
  local -a current_items updated_items

  [[ -n "$requested_value" ]] || die "$(msg missing_option_arg "$OPT")"
  if [[ ! "$requested_value" =~ ^[[:alnum:]_.+-]+$ ]]; then
    die "$(msg invalid_setting "$setting_name" "$requested_value")"
  fi

  mkdir -p "$(dirname "$script_conf")"
  touch "$script_conf"
  while IFS= read -r line; do
    if [[ "$line" =~ $setting_pattern ]]; then
      current_value="${BASH_REMATCH[1]}"
      current_value="${current_value#\"}"
      current_value="${current_value%\"}"
      current_value="${current_value#\'}"
      current_value="${current_value%\'}"
      break
    fi
  done < "$script_conf"

  IFS='|' read -r -a current_items <<< "$current_value"
  for item in "${current_items[@]}"; do
    item_trimmed="${item#"${item%%[![:space:]]*}"}"
    item_trimmed="${item_trimmed%"${item_trimmed##*[![:space:]]}"}"
    [[ -n "$item_trimmed" ]] || continue
    if [[ "${item_trimmed,,}" == "${requested_value,,}" ]]; then
      value_found=1
      [[ "$action" == "remove" ]] && continue
    fi
    updated_items+=("$item_trimmed")
  done

  if [[ "$action" == "add" ]]; then
    if (( value_found )); then
      echo "$(msg list_contains "$setting_name" "$requested_value")"
      return 0
    fi
    updated_items+=("$requested_value")
  elif (( ! value_found )); then
    echo "$(msg list_not_contains "$setting_name" "$requested_value")"
    return 0
  fi

  config_value=$(IFS='|'; echo "${updated_items[*]}")
  local config_temp
  config_temp=$(mktemp "$(dirname "$script_conf")/.${script_name}.conf.XXXXXX") || die "$(msg temp_config_failed)"
  local setting_written=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ $setting_pattern ]]; then
      if (( ! setting_written )); then
        printf '%s="%s"\n' "$setting_name" "$config_value" >> "$config_temp"
        setting_written=1
      fi
    else
      printf '%s\n' "$line" >> "$config_temp"
    fi
  done < "$script_conf"
  if (( ! setting_written )); then
    printf '%s="%s"\n' "$setting_name" "$config_value" >> "$config_temp"
  fi
  chmod --reference="$script_conf" "$config_temp" 2>/dev/null || true
  mv -f "$config_temp" "$script_conf"
  echo "$(msg list_updated "$setting_name" "$config_value")"
}

while getopts :eushf:cm:l:-: OPT; do
  # support long options: https://stackoverflow.com/a/28466267/519360
  if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
    OPT="${OPTARG%%=*}"       # extract long option name
    OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
    OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
  fi
  case "$OPT" in
    h | help )
            echo -e "\033[1m$(msg help_title "$script_name_cap")\033[0m"
            echo
            msg help "$script_bin"
            exit 0
            ;;
    add-skip_list )
            needs_long_arg "$@"
            update_config_list add "$OPTARG" skip_list "remux|vostfr|hdtv"
            exit 0
            ;;
    remove-skip_list )
            needs_long_arg "$@"
            update_config_list remove "$OPTARG" skip_list "remux|vostfr|hdtv"
            exit 0
            ;;
    add-banned_teams )
            needs_long_arg "$@"
            update_config_list add "$OPTARG" banned_teams ""
            exit 0
            ;;
    remove-banned_teams )
            needs_long_arg "$@"
            update_config_list remove "$OPTARG" banned_teams ""
            exit 0
            ;;
    f | find )
            needs_arg
            arg_search_value="$OPTARG"
            echo -e "\033[1m$(msg find_title "$script_name_cap")\033[0m"
            echo "$(msg root_required)"
            echo ""
            echo "$(msg root_check)"
            source "$script_conf" 2>/dev/null
            if [[ "$sudo" == "" ]] && [[ "$EUID" != "0" ]]; then
              echo "$(msg root_missing)"
            else
              echo "$(msg root_granted)"
            fi
            echo "$(msg db_updating)"
            echo "$sudo" | sudo -kS updatedb 2>/dev/null
            logs_path=`echo "$sudo" | sudo -kS locate -r "/$script_name/logs$" 2>/dev/null`
            echo "$(msg searching)"
            for log_path in $logs_path ; do
              my_logs=( `echo "$sudo" | sudo -kS find $log_path -type f 2>/dev/null` )
              for my_log in "${my_logs[@]}" ; do
                echo "$sudo" | sudo -kS grep -Hin "$arg_search_value" "$my_log" 2>/dev/null
              done
            done
            exit 0
            ;;
    u | update )
            echo -e "\033[1m$(msg update_title "$script_name_cap")\033[0m"
            read -r -n 1 -p "$(msg update_confirm)" yn
            printf "\r                                                     "
            if [[ "${yn}" == @(y|Y|o|O) ]]; then
              echo ""
              this_script=$(realpath -s "$0")
              echo "$(msg script_location "$this_script")"
              if curl -m 2 --head --silent --fail "$script_remote" 2>/dev/null >/dev/null; then
                echo "$(msg script_online)"
                md5_local=`md5sum "$this_script" | cut -f1 -d" " 2>/dev/null`
                md5_remote=`curl -s "$script_remote" | md5sum | cut -f1 -d" "`
                echo "$(msg md5_local "$md5_local")"
                echo "$(msg md5_remote "$md5_remote")"
                if [[ "$md5_local" != "$md5_remote" ]]; then
                  echo "$(msg update_available)"
                  curl -s -m 3 --create-dir -o "$this_script" "$script_remote"
                  echo "$(msg update_complete)"
                else
                  echo "$(msg script_current)"
                fi
              else
                echo ""
                echo "$(msg script_offline)"
              fi
            else
              echo ""
              echo "$(msg nothing_done)"
            fi
            exit 0
            ;;
    c | cron-log )
            echo -e "\033[1m$(msg cron_log_title "$script_name_cap")\033[0m"
            echo ""
            if [[ -f "$script_cron_log" ]]; then
              date_log=`date -r "$script_cron_log" `
              cat "$script_cron_log"
              echo ""
              echo "$(msg log_created "$date_log")"
            else
              echo "$(msg no_log)"
            fi
            exit 0
            ;;
    m | mode )
            needs_arg
            arg_display_mode="$OPTARG"
            display_mode_supported=( "full" )
            echo -e "\033[1m$(msg mode_title "$script_name_cap")\033[0m"
            echo ""
            if [[ "$arg_display_mode" == "full" ]]; then
              echo "$(msg mode_enabled "$arg_display_mode")"
            else
              echo "$(msg mode_unsupported "$arg_display_mode")"
              exit 0
            fi
            ;;
    l | language )
            needs_arg
            selected_language="${OPTARG%%.*}"
            selected_language="${selected_language%%_*}"
            selected_language="${selected_language,,}"
            echo
            if [[ "$selected_language" == "$display_language" ]]; then
              echo "$(msg language_selected "$selected_language")"
            else
              echo "$(msg language_fallback "$OPTARG")"
            fi
            ;;
    e | edit-config )
            eval next_arg=\${$OPTIND}
            if [[ "$next_arg" == "" ]]; then
              echo -e "\033[1m$(msg editor_title "$script_name_cap")\033[0m"
              echo ""
              echo "$(msg editor_default)"
              nano "$script_conf"
              exit 0
            else
              echo -e "\033[1m$(msg editor_title "$script_name_cap")\033[0m"
              echo ""
              if command -v $next_arg ; then
                echo "$(msg editor_using "$next_arg")"
                $next_arg "$script_conf"
              else
                echo "$(msg editor_missing "$next_arg")"
              fi
              exit 0
            fi
            ;;
    s | status )
            echo -e "\033[1m$(msg status_title "$script_name_cap")\033[0m"
            echo ""
            eval next_arg=\${$OPTIND}
            if [[ "$next_arg" == @(|status) ]]; then
              echo "$(msg scheduler_check)"
              crontab -l > "$script_tmp_folder/my_old_cron.txt"
              cron_check=`cat "$script_tmp_folder/my_old_cron.txt" | grep $script_name`
              if [[ "$cron_check" != "" ]]; then
                echo "$(msg cron_added)"
                cron_status=`cat "$script_tmp_folder/my_old_cron.txt" | grep $script_name | grep "^#"`
                if [[ "$cron_status" == "" ]]; then
                  echo "$(msg cron_enabled)"
                else
                  echo "$(msg cron_disabled)"
                fi
              else
                echo "$(msg cron_not_added)"
              fi
            elif [[ "$next_arg" == "enable" ]]; then
              echo "$(msg cron_enabling)"
              crontab -l > "$script_tmp_folder/my_old_cron.txt"
              safety_check=`cat "$script_tmp_folder/my_old_cron.txt" | grep $script_name | grep "^#"`
              if [[ "$safety_check" != "" ]]; then
                cat "$script_tmp_folder/my_old_cron.txt" | grep $script_name | sed  's/^#//' > "$script_tmp_folder/my_new_cron.txt"
                crontab "$script_tmp_folder/my_new_cron.txt"
              else
                echo "$(msg already_enabled)"
              fi
            elif [[ "$next_arg" == "disable" ]]; then
              echo "$(msg cron_disabling)"
              crontab -l > "$script_tmp_folder/my_old_cron.txt"
              safety_check=`cat "$script_tmp_folder/my_old_cron.txt" | grep $script_name | grep "^#"`
              if [[ "$safety_check" == "" ]]; then
                cat "$script_tmp_folder/my_old_cron.txt" | grep $script_name | sed 's/^/#/' > "$script_tmp_folder/my_new_cron.txt"
                crontab "$script_tmp_folder/my_new_cron.txt"
              else
                echo "$(msg already_disabled)"
              fi
            fi
            rm "$script_tmp_folder/my_old_cron.txt" 2>/dev/null
            rm "$script_tmp_folder/my_new_cron.txt" 2>/dev/null
            exit 0
            ;;
    ??* )          die "$(msg illegal_option "$OPT")" ;;
    : )            die "$(msg missing_option_arg "$OPTARG")" ;;
    ? )            die "$(msg illegal_option "$OPTARG")" ;;
  esac
done
shift $((OPTIND-1)) # remove parsed options and args from $@ list


#######################
## Log everything displayed during this execution
execution_date=$(date +%Y-%m-%d)
execution_time=$(date +%H-%M-%S)
execution_log_folder="$script_folder/logs/$execution_date"
mkdir -p "$execution_log_folder"
execution_log="$execution_log_folder/$execution_time.txt"
exec > >(tee -a "$execution_log") 2>&1


#######################
## Script configuration
push_notification_movie_added_default="${MUI[notification_movie]}"
push_notification_serie_added_default="${MUI[notification_series]}"
push_notification_stopped_default="${MUI[notification_stopped]}"
settings_variables=( sudo c411_api_key betaseries_api_key betaseries_api_secret betaseries_token plex_section_series transmission_login transmission_password transmission_ip transmission_port transmission_torrent_paused plex_sort_folder skip_list banned_teams approved_teams resolution_preference codec_preference imdb_minimum filebot_films filebot_films_H265 filebot_series filebot_series_H265 push_token_app push_target push_ignored push_notification_movie_added push_notification_serie_added push_notification_stopped )
required_settings=( c411_api_key transmission_login transmission_password transmission_ip transmission_port plex_sort_folder filebot_films filebot_series )
edit_conf=0
mkdir -p "$(dirname "$script_conf")"
touch "$script_conf"
chmod 600 "$script_conf"
for script_variable in "${settings_variables[@]}"; do
  if ! grep -qE "^[[:space:]]*${script_variable}[[:space:]]*=" "$script_conf"; then
    case "$script_variable" in
      push_notification_movie_added)
        printf 'push_notification_movie_added="%s"\n' "$push_notification_movie_added_default" >> "$script_conf"
        ;;
      push_notification_serie_added)
        printf 'push_notification_serie_added="%s"\n' "$push_notification_serie_added_default" >> "$script_conf"
        ;;
      push_notification_stopped)
        printf 'push_notification_stopped="%s"\n' "$push_notification_stopped_default" >> "$script_conf"
        ;;
      transmission_torrent_paused)
        printf 'transmission_torrent_paused="no"\n' >> "$script_conf"
        ;;
      skip_list)
        printf 'skip_list="remux|vostfr|hdtv"\n' >> "$script_conf"
        ;;
      *)
        printf '%s=""\n' "$script_variable" >> "$script_conf"
        edit_conf=1
        ;;
    esac
  fi
done
if (( edit_conf )); then
  echo "$(msg edit_configuration)"
  echo "$(msg use_edit "$script_bin")"
  exit 0
fi

# Read the template literally so variables inside double quotes are expanded
# only when the notification is created, not when the config is sourced.
push_notification_movie_added_literal=""
push_notification_serie_added_literal=""
push_notification_stopped_literal=""
while IFS= read -r config_line; do
  if [[ "$config_line" =~ ^[[:space:]]*push_notification_movie_added[[:space:]]*=(.*)$ ]]; then
    push_notification_movie_added_literal="${BASH_REMATCH[1]}"
  elif [[ "$config_line" =~ ^[[:space:]]*push_notification_serie_added[[:space:]]*=(.*)$ ]]; then
    push_notification_serie_added_literal="${BASH_REMATCH[1]}"
  elif [[ "$config_line" =~ ^[[:space:]]*push_notification_stopped[[:space:]]*=(.*)$ ]]; then
    push_notification_stopped_literal="${BASH_REMATCH[1]}"
  fi
done < "$script_conf"
push_notification_movie_added_literal=$(
  printf '%s' "$push_notification_movie_added_literal" |
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
)
if (( ${#push_notification_movie_added_literal} >= 2 )); then
  first_quote="${push_notification_movie_added_literal:0:1}"
  last_quote="${push_notification_movie_added_literal: -1}"
  if [[ ( "$first_quote" == '"' && "$last_quote" == '"' ) || ( "$first_quote" == "'" && "$last_quote" == "'" ) ]]; then
    push_notification_movie_added_literal="${push_notification_movie_added_literal:1:${#push_notification_movie_added_literal}-2}"
  fi
fi
push_notification_serie_added_literal=$(
  printf '%s' "$push_notification_serie_added_literal" |
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
)
if (( ${#push_notification_serie_added_literal} >= 2 )); then
  first_quote="${push_notification_serie_added_literal:0:1}"
  last_quote="${push_notification_serie_added_literal: -1}"
  if [[ ( "$first_quote" == '"' && "$last_quote" == '"' ) || ( "$first_quote" == "'" && "$last_quote" == "'" ) ]]; then
    push_notification_serie_added_literal="${push_notification_serie_added_literal:1:${#push_notification_serie_added_literal}-2}"
  fi
fi
push_notification_stopped_literal=$(
  printf '%s' "$push_notification_stopped_literal" |
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
)
if (( ${#push_notification_stopped_literal} >= 2 )); then
  first_quote="${push_notification_stopped_literal:0:1}"
  last_quote="${push_notification_stopped_literal: -1}"
  if [[ ( "$first_quote" == '"' && "$last_quote" == '"' ) || ( "$first_quote" == "'" && "$last_quote" == "'" ) ]]; then
    push_notification_stopped_literal="${push_notification_stopped_literal:1:${#push_notification_stopped_literal}-2}"
  fi
fi
source "$script_conf"
push_notification_movie_added="${push_notification_movie_added_literal:-$push_notification_movie_added_default}"
push_notification_serie_added="${push_notification_serie_added_literal:-$push_notification_serie_added_default}"
push_notification_stopped="${push_notification_stopped_literal:-$push_notification_stopped_default}"

save-config-value() {
  local setting_name="$1" setting_value="$2" line temp_file written=0
  local setting_pattern="^[[:space:]]*${setting_name}[[:space:]]*="

  temp_file=$(mktemp "$(dirname "$script_conf")/.${script_name}.conf.XXXXXX") || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ $setting_pattern ]]; then
      if (( ! written )); then
        printf '%s=%q\n' "$setting_name" "$setting_value" >> "$temp_file"
        written=1
      fi
    else
      printf '%s\n' "$line" >> "$temp_file"
    fi
  done < "$script_conf"
  if (( ! written )); then
    printf '%s=%q\n' "$setting_name" "$setting_value" >> "$temp_file"
  fi
  chmod 600 "$temp_file"
  mv -f "$temp_file" "$script_conf"
}

transmission_torrent_paused="${transmission_torrent_paused,,}"
if [[ "$transmission_torrent_paused" != "yes" && "$transmission_torrent_paused" != "no" ]]; then
  echo "$(msg invalid_paused "$transmission_torrent_paused")"
  exit 1
fi

resolution_preference="${resolution_preference,,}"
case "$resolution_preference" in
  ""|1080|1080p|fhd)
    resolution_preference="1080p"
    resolution_pattern='1080p'
    resolution_target_standard="1080p"
    ;;
  2160|2160p|4k|uhd)
    resolution_preference="4K"
    resolution_pattern='2160p|4k|uhd'
    resolution_target_standard="4K"
    ;;
  720|720p|hd)
    resolution_preference="720p"
    resolution_pattern='720p'
    resolution_target_standard="720p"
    ;;
  *)
    echo "$(msg invalid_resolution "$resolution_preference")"
    exit 1
    ;;
esac

imdb_minimum="${imdb_minimum//,/.}"
if [[ -n "$imdb_minimum" ]]; then
  if [[ ! "$imdb_minimum" =~ ^[0-9]+([.][0-9]+)?$ ]] || ! awk -v minimum="$imdb_minimum" 'BEGIN { exit !(minimum >= 0 && minimum <= 10) }'; then
    echo "$(msg invalid_imdb "$imdb_minimum")"
    exit 1
  fi
fi

case "${codec_preference,,}" in
  h264|x264|avc)
    codec_preference="H264"
    ;;
  h265|x265|hevc)
    codec_preference="H265"
    ;;
  av1)
    codec_preference="AV1"
    ;;
  *)
    codec_preference=""
    ;;
esac

#######################
## Import missing values
conky_conf="$HOME/.conky/conky-nas.conf"
if [[ -r "$conky_conf" ]]; then
  for variable in "${required_settings[@]}"; do
    [[ -n "${!variable:-}" ]] && continue
    value=$(
      bash -c '
        source "$1" 2>/dev/null
        printf "%s" "${!2-}"
      ' _ "$conky_conf" "$variable"
    )
    if [[ -n "$value" ]]; then
      printf -v "$variable" '%s' "$value"
      printf -v escaped_value '%q' "$value"
      sed -i -E "s|^[[:space:]]*${variable}[[:space:]]*=.*$|${variable}=\"${escaped_value}\"|" "$script_conf"
      echo "$(msg config_imported "$variable" "$conky_conf")"
    fi
  done
fi
if [[ -z "${plex_sort_folder:-}" ]]; then
  plex_sort_conf=$(find /home -type f -path "*/.config/plex_sort/plex_sort.conf" 2>/dev/null | head -n1)
  if [[ -n "$plex_sort_conf" ]]; then
    plex_sort_folder=$(dirname "$plex_sort_conf")
    if grep -qE '^plex_sort_folder=' "$script_conf"; then
      sed -i "s|^plex_sort_folder=.*|plex_sort_folder=\"$plex_sort_folder\"|" "$script_conf"
    else
      printf 'plex_sort_folder="%s"\n' "$plex_sort_folder" >> "$script_conf"
    fi
    echo "$(msg config_imported plex_sort_folder "$plex_sort_conf")"
  fi
fi
plex_sort_config="$plex_sort_folder/plex_sort.conf"
if [[ -r "$plex_sort_config" ]]; then
  download_folder=$(sed -nE 's|^[[:space:]]*download_folder[[:space:]]*=[[:space:]]*"([^"]*)".*$|\1|p' "$plex_sort_config" | head -n1)
  if [[ -z "${push_token_app:-}" ]]; then
    push_token_app=$(bash -c 'source "$1"; printf "%s" "${token_app:-}"' _ "$plex_sort_config")
  fi
  if [[ -z "${push_target:-}" ]]; then
    push_target=$(bash -c 'source "$1"; printf "%s" "${target_1:-}"' _ "$plex_sort_config")
  fi
fi
if [[ -n "$download_folder" ]]; then
  if [[ -z "${filebot_films:-}" || -z "${filebot_films_H265:-}" || -z "${filebot_series:-}" || -z "${filebot_series_H265:-}" ]]; then
    while IFS= read -r folder; do
      folder_name_lower=${folder##*/}
      folder_name_lower=${folder_name_lower,,}
      [[ "$folder_name_lower" == *filebot* ]] || continue
      if [[ "$folder_name_lower" == *films* ]]; then
        if [[ "$folder_name_lower" == *h265* ]]; then
          filebot_films_H265="$folder"
        else
          filebot_films="$folder"
        fi
      elif [[ "$folder_name_lower" == *series* ]]; then
        if [[ "$folder_name_lower" == *h265* ]]; then
          filebot_series_H265="$folder"
        else
          filebot_series="$folder"
        fi
      fi
    done < <(find "$download_folder" -mindepth 1 -maxdepth 1 -type d)
    for variable in filebot_films filebot_films_H265 filebot_series filebot_series_H265; do
      value=${!variable:-}
      [[ -n "$value" ]] || continue
      if grep -qE "^${variable}=" "$script_conf"; then
        sed -i "s|^${variable}=.*|${variable}=\"$value\"|" "$script_conf"
      else
        printf '%s="%s"\n' "$variable" "$value" >> "$script_conf"
      fi
      echo "$(msg config_imported_value "$variable" "$value")"
    done
  fi
fi


#######################
## Validate required settings
missing_value=0
for variable in "${required_settings[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    echo "$(msg missing_config "$variable")"
    missing_value=1
  fi
done
if (( missing_value )); then
  echo "$(msg use_edit "$script_bin")"
  exit 1
fi


#######################
## Fix printf special char issue
Lengh1="55"
Lengh2="61"
lon() ( echo $(( Lengh1 + $(wc -c <<<"$1") - $(wc -m <<<"$1") )) )
lon2() ( echo $(( Lengh2 + $(wc -c <<<"$1") - $(wc -m <<<"$1") )) )

show-execution-end() {
  local exit_status="$1"
  local executed_date
  executed_date=$(date)
  trap - EXIT
  echo ""
  printf "\e[46m \u23E5\u23E5\u23E5 \e[0m \e[46m  %*s  \e[0m \e[46m  \e[0m \e[46m \e[0m \e[36m\u2759\e[0m\n" "$(lon2 "$executed_date")" "$executed_date"
  exit "$exit_status"
}
trap 'show-execution-end "$?"' EXIT


#######################
## UI tags
ui_tag_ok="[\e[42m \u2713 \e[0m]"
ui_tag_bad="[\e[41m \u2717 \e[0m]"
ui_tag_info="[ \u2794 ]"
ui_tag_processed="[...]"
ui_tag_warning="[\e[43m \u2713 \e[0m]"
ui_tag_section="\e[44m[\u2263\u2263\u2263]\e[0m \e[44m \e[1m %-*s  \e[0m \e[44m  \e[0m \e[44m \e[0m \e[34m\u2759\e[0m\n"
printf "\e[46m \u23E5\u23E5\u23E5 \e[0m \e[46m \e[1m %-61s  \e[0m \e[46m  \e[0m \e[46m \e[0m \e[36m\u2759\e[0m\n" "$script_name_cap"
echo -e "$ui_tag_processed $(msg execution_log "$execution_log")"


#######################
## Push feature
push-message() {
  local push_title="$1"
  local push_content="$2"
  local push_priority="${3:--1}"
  local push_url="${4:-}"
  local push_url_title="${5:-}"
  local push_attachment="${6:-}"
  local -a curl_args=(
    --silent --show-error --fail --max-time 20
    --form-string "token=$push_token_app"
    --form-string "user=$push_target"
    --form-string "title=$push_title"
    --form-string "message=$push_content"
    --form-string "html=1"
    --form-string "priority=$push_priority"
  )

  [[ -n "${push_token_app:-}" && -n "${push_target:-}" ]] || return 2

  if [[ -n "$push_url" ]]; then
    curl_args+=(--form-string "url=$push_url")
    curl_args+=(--form-string "url_title=${push_url_title:-$(msg view_tmdb)}")
  fi
  if [[ -s "$push_attachment" ]]; then
    curl_args+=(--form "attachment=@$push_attachment;type=image/jpeg")
  fi

  curl "${curl_args[@]}" "https://api.pushover.net/1/messages.json" > /dev/null
}

render-push-notification() (
  local notification="$1"

  # Keep replacement values literal, notably ampersands in titles and plots.
  shopt -u patsub_replacement 2>/dev/null || true
  notification="${notification//\\n/$'\n'}"
  notification="${notification//\$\{title\}/$title}"
  notification="${notification//\$title/$title}"
  notification="${notification//\$\{enabled_name\}/$enabled_name}"
  notification="${notification//\$enabled_name/$enabled_name}"
  notification="${notification//\$\{episode_name\}/$enabled_name}"
  notification="${notification//\$episode_name/$enabled_name}"
  notification="${notification//\$\{torrent_name\}/$torrent_name}"
  notification="${notification//\$torrent_name/$torrent_name}"
  notification="${notification//\$\{torrent_codec\}/$torrent_codec}"
  notification="${notification//\$torrent_codec/$torrent_codec}"
  notification="${notification//\$\{transmission_folder\}/$transmission_folder}"
  notification="${notification//\$transmission_folder/$transmission_folder}"
  notification="${notification//\$\{transmission_state\}/$transmission_state}"
  notification="${notification//\$transmission_state/$transmission_state}"
  notification="${notification//\$\{movie_name\}/$movie_name}"
  notification="${notification//\$movie_name/$movie_name}"
  notification="${notification//\$\{serie_name\}/$movie_name}"
  notification="${notification//\$serie_name/$movie_name}"
  notification="${notification//\$\{filebot_name\}/$movie_name}"
  notification="${notification//\$filebot_name/$movie_name}"
  notification="${notification//\$\{imdb_rating\}/$imdb_rating}"
  notification="${notification//\$imdb_rating/$imdb_rating}"
  notification="${notification//\$\{imdb_minimum\}/$imdb_minimum}"
  notification="${notification//\$imdb_minimum/$imdb_minimum}"
  notification="${notification//\$\{imdb_id\}/$movie_imdb_id}"
  notification="${notification//\$imdb_id/$movie_imdb_id}"
  notification="${notification//\$\{movie_imdb_id\}/$movie_imdb_id}"
  notification="${notification//\$movie_imdb_id/$movie_imdb_id}"
  notification="${notification//\$\{tmdb_id\}/$movie_tmdb_id}"
  notification="${notification//\$tmdb_id/$movie_tmdb_id}"
  notification="${notification//\$\{movie_tmdb_id\}/$movie_tmdb_id}"
  notification="${notification//\$movie_tmdb_id/$movie_tmdb_id}"
  notification="${notification//\$\{tmdb_url\}/$movie_tmdb_url}"
  notification="${notification//\$tmdb_url/$movie_tmdb_url}"
  notification="${notification//\$\{tvdb_id\}/$series_tvdb_id}"
  notification="${notification//\$tvdb_id/$series_tvdb_id}"
  notification="${notification//\$\{tvdb_url\}/$series_tvdb_url}"
  notification="${notification//\$tvdb_url/$series_tvdb_url}"
  notification="${notification//\$\{synopsis\}/$movie_synopsis}"
  notification="${notification//\$synopsis/$movie_synopsis}"
  notification="${notification//\$\{movie_synopsis\}/$movie_synopsis}"
  notification="${notification//\$movie_synopsis/$movie_synopsis}"

  if (( ${#notification} > 1024 )); then
    notification="${notification:0:1021}..."
  fi
  printf '%s' "$notification"
)

render-stopped-push-notification() (
  local stopped_torrent_name="$1"
  local notification="$push_notification_stopped"

  shopt -u patsub_replacement 2>/dev/null || true
  notification="${notification//\\n/$'\n'}"
  notification="${notification//\$\{torrent_name\}/$stopped_torrent_name}"
  notification="${notification//\$torrent_name/$stopped_torrent_name}"

  if (( ${#notification} > 1024 )); then
    notification="${notification:0:1021}..."
  fi
  printf '%s' "$notification"
)


#######################
## Loading spinner
function display_loading() {
  pid="$*"
  if [[ "$mui_loading_spinner" == "" ]]; then                                               ## MUI
    mui_loading_spinner="$(msg loading)"                                                    ##
  fi                                                                                        ##
  lengh_spinner=${#mui_loading_spinner}
  if [[ "$loading_spinner" == "" ]]; then
    spin='⣾⣽⣻⢿⡿⣟⣯⣷'
  else
    spin=$loading_spinner
  fi
  charwidth=1
  i=0
  tput civis # cursor invisible
  mon_printf="\r                                                                             "
  while kill -0 "$pid" 2>/dev/null; do
    i=$(((i + $charwidth) % ${#spin}))
    printf "\r[\e[43m \u039E \e[0m] %"$lengh_spinner"s %s" "$mui_loading_spinner" "${spin:$i:$charwidth}"
    sleep .1
  done
  tput cnorm
  printf "$mon_printf" && printf "\r"
}


#######################
## Get movie informations
get-movie-metadata() {
  local movie_query="$1"
  local rss_tmdb_id="$2"
  local metadata english_metadata
  local english_synopsis english_rating english_imdb_id english_tmdb_id english_poster_url
  local metadata_format=$'{info.Overview}\x1f{omdb.rating}\x1f{imdbid}\x1f{tmdbid}\x1f{info.Poster}'
  local -a metadata_args=( -list --q "$movie_query" --db TheMovieDB --format "$metadata_format" --log OFF )

  movie_synopsis=""
  movie_imdb_rating=""
  movie_imdb_id=""
  movie_tmdb_id=""
  movie_poster_url=""
  movie_tmdb_url=""

  # The FileBot name identifies each movie independently in multi-movie torrents.
  metadata=$(filebot "${metadata_args[@]}" --lang fr 2>/dev/null)
  if [[ -z "$metadata" && "$rss_tmdb_id" =~ ^[0-9]+$ ]]; then
    metadata=$(filebot "${metadata_args[@]}" --lang fr --filter "id == $rss_tmdb_id" 2>/dev/null)
  fi
  IFS=$'\x1f' read -r movie_synopsis movie_imdb_rating movie_imdb_id movie_tmdb_id movie_poster_url <<< "${metadata%%$'\n'*}"

  if [[ -z "${movie_synopsis//[[:space:]]/}" ]]; then
    english_metadata=$(filebot "${metadata_args[@]}" --lang en 2>/dev/null)
    IFS=$'\x1f' read -r english_synopsis english_rating english_imdb_id english_tmdb_id english_poster_url <<< "${english_metadata%%$'\n'*}"
    movie_synopsis="$english_synopsis"
    [[ -n "$movie_imdb_rating" ]] || movie_imdb_rating="$english_rating"
    [[ -n "$movie_imdb_id" ]] || movie_imdb_id="$english_imdb_id"
    [[ -n "$movie_tmdb_id" ]] || movie_tmdb_id="$english_tmdb_id"
    [[ -n "$movie_poster_url" ]] || movie_poster_url="$english_poster_url"
  fi

  if [[ -z "${movie_synopsis//[[:space:]]/}" ]]; then
    movie_synopsis="$(msg synopsis_unavailable)"
  elif (( ${#movie_synopsis} > 600 )); then
    movie_synopsis="${movie_synopsis:0:597}..."
  fi
  [[ "$movie_imdb_rating" =~ ^[0-9]+([.][0-9]+)?$ ]] || movie_imdb_rating="$(msg unavailable)"
  [[ "$movie_imdb_id" =~ ^tt[0-9]+$ ]] || movie_imdb_id="$(msg unavailable)"
  if [[ "$movie_tmdb_id" =~ ^[0-9]+$ ]]; then
    movie_tmdb_url="https://www.themoviedb.org/movie/$movie_tmdb_id?language=fr-FR"
  else
    movie_tmdb_id="$(msg unavailable)"
  fi
  if [[ "$movie_poster_url" == https://image.tmdb.org/t/p/* ]]; then
    movie_poster_url="${movie_poster_url/\/original\//\/w500\/}"
  else
    movie_poster_url=""
  fi
}

get-series-metadata() {
  local series_query="$1"
  local metadata
  local metadata_format=$'{tvdbid}\x1f{info.Poster}'

  series_tvdb_id=""
  series_tvdb_url=""
  movie_poster_url=""
  metadata=$(filebot -list --q "$series_query" --db TheTVDB --format "$metadata_format" --log OFF 2>/dev/null)
  IFS=$'\x1f' read -r series_tvdb_id movie_poster_url <<< "${metadata%%$'\n'*}"

  if [[ "$series_tvdb_id" =~ ^[0-9]+$ ]]; then
    series_tvdb_url="https://thetvdb.com/dereferrer/series/$series_tvdb_id"
  else
    series_tvdb_id="$(msg unavailable)"
  fi
  if [[ "$movie_poster_url" != https://artworks.thetvdb.com/* ]]; then
    movie_poster_url=""
  fi
}

imdb-rating-meets-minimum() {
  local rating="$1"
  local minimum="$2"
  awk -v rating="$rating" -v minimum="$minimum" 'BEGIN { exit !(rating >= minimum) }'
}

resolution-standard() {
  local width="$1"
  local height="$2"
  [[ "$width" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ ]] || {
    echo "Unknown"
    return 1
  }
  if (( height > width )); then
    local tmp=$width
    width=$height
    height=$tmp
  fi
  if (( width >= 3648 || height >= 2052 )); then
    echo "4K"
  elif (( width >= 1824 || height >= 1026 )); then
    echo "1080p"
  elif (( width >= 1216 || height >= 684 )); then
    echo "720p"
  else
    echo "SD"
  fi
}
resolution-rank() {
  case "$1" in
    SD) echo 0 ;;
    720p) echo 1 ;;
    1080p) echo 2 ;;
    4K) echo 3 ;;
    *) echo -1 ;;
  esac
}
codec-standard() {
  local codec="${1^^}"   # Upper the codec name
  case "$codec" in
    HEVC) echo "H265" ;;
    AVC)  echo "H264" ;;
    AV1)  echo "AV1" ;;
    VP9)  echo "VP9" ;;
    MPEG-4*|MPEG4) echo "MPEG-4" ;;
    MPEG*VIDEO) echo "MPEG-2" ;;
    VC-1) echo "VC-1" ;;
    *) echo "$codec" ;;
  esac
}
detect-codec-from-name() {
  local text="${1,,}"
  if [[ "$text" == *"h265"* || "$text" == *"x265"* || "$text" == *"hevc"* ]]; then
    echo "H265"
  elif [[ "$text" == *"h264"* || "$text" == *"x264"* || "$text" == *"avc"* ]]; then
    echo "H264"
  elif [[ "$text" == *"av1"* ]]; then
    echo "AV1"
  else
    echo "Unknown"
  fi
}
release_team_from_name() {
  local name="${1,,}"
  local teams="$2"
  local team team_lower team_length prefix_length previous_char

  name=${name%.mkv}
  name=${name%.mp4}
  name=${name%.avi}
  while [[ "$name" == *']' || "$name" == *')' ]]; do
    name=${name%?}
  done

  while IFS= read -r team; do
    [[ -n "$team" ]] || continue
    team_lower=${team,,}
    team_length=${#team_lower}
    if [[ "${name: -team_length}" == "$team_lower" ]]; then
      prefix_length=$((${#name} - team_length))
      if (( prefix_length == 0 )); then
        printf '%s\n' "$team"
        return 0
      fi
      previous_char=${name:prefix_length-1:1}
      if [[ ! "$previous_char" =~ [[:alnum:]] ]]; then
        printf '%s\n' "$team"
        return 0
      fi
    fi
  done < <(printf '%s\n' "$teams" | tr '|,[:space:]' '\n' | sort -fu)

  return 1
}

get-betaseries-member-id() {
  local response_file="$1" http_code

  [[ -n "${betaseries_token:-}" ]] || return 1
  if ! http_code=$(curl --silent --show-error \
    --connect-timeout 10 \
    --max-time 30 \
    --output "$response_file" \
    --write-out '%{http_code}' \
    --header "X-BetaSeries-Key: $betaseries_api_key" \
    --header 'X-BetaSeries-Version: 3.0' \
    --header "Authorization: Bearer $betaseries_token" \
    --header "User-Agent: $script_name/1.0" \
    'https://api.betaseries.com/members/infos'); then
    return 2
  fi
  betaseries_member_id=$(jq -r '.member.id // empty' "$response_file" 2>/dev/null)
  [[ "$http_code" =~ ^2[0-9][0-9]$ && -n "$betaseries_member_id" ]]
}

request-betaseries-token() {
  local response_file="$1" access_token device_code expires_at expires_in interval user_code verification_url

  if [[ ! -t 0 ]]; then
    echo "$(msg oauth_interactive)" >&2
    return 1
  fi
  if [[ -z "${betaseries_api_secret:-}" ]]; then
    read -r -s -p "$(msg oauth_secret)" betaseries_api_secret
    echo
  fi
  [[ -n "$betaseries_api_secret" ]] || return 1

  if ! curl --silent --show-error --fail-with-body \
    --connect-timeout 10 \
    --max-time 30 \
    --request POST \
    --output "$response_file" \
    --header "X-BetaSeries-Key: $betaseries_api_key" \
    --header 'X-BetaSeries-Version: 3.0' \
    --header "User-Agent: $script_name/1.0" \
    'https://api.betaseries.com/oauth/device'; then
    return 1
  fi

  device_code=$(jq -r '.device_code // empty' "$response_file")
  user_code=$(jq -r '.user_code // empty' "$response_file")
  verification_url=$(jq -r '.verification_url // empty' "$response_file")
  expires_in=$(jq -r '.expires_in // 1800' "$response_file")
  interval=$(jq -r '.interval // 5' "$response_file")
  [[ -n "$device_code" && -n "$user_code" && -n "$verification_url" ]] || return 1

  msg oauth_open "$verification_url" "$user_code"
  msg oauth_waiting
  expires_at=$(( $(date +%s) + expires_in ))
  while (( $(date +%s) < expires_at )); do
    sleep "$interval"
    printf '.'
    if curl --silent --show-error \
      --connect-timeout 10 \
      --max-time 30 \
      --request POST \
      --output "$response_file" \
      --header "X-BetaSeries-Key: $betaseries_api_key" \
      --header 'X-BetaSeries-Version: 3.0' \
      --data-urlencode "client_id=$betaseries_api_key" \
      --data-urlencode "client_secret=$betaseries_api_secret" \
      --data-urlencode "code=$device_code" \
      'https://api.betaseries.com/oauth/access_token'; then
      access_token=$(jq -r '.access_token // empty' "$response_file" 2>/dev/null)
      if [[ -n "$access_token" ]]; then
        msg oauth_authorized
        betaseries_token=$access_token
        save-config-value betaseries_token "$betaseries_token" || return 1
        return 0
      fi
    fi
  done
  msg oauth_expired >&2
  return 1
}

generate-series-watchlist() {
  local destination="$1" temp_dir response_file beta_file plex_file merged_file http_code betaseries_count
  local plex_conf="$HOME/.conky/conky-nas.conf" plex_ip plex_port plex_token plex_scheme plex_host plex_base_url
  local plex_section_key auth_status betaseries_available
  local -a plex_settings

  [[ -n "${plex_section_series:-}" ]] || {
    echo "$(msg missing_plex_section)" >&2
    return 1
  }
  [[ -r "$plex_conf" ]] || return 1

  temp_dir=$(mktemp -d "$script_tmp_folder/c411-watchlist.XXXXXX") || return 1
  response_file="$temp_dir/response.json"
  beta_file="$temp_dir/betaseries.jsonl"
  plex_file="$temp_dir/plex.jsonl"
  merged_file="$temp_dir/merged.jsonl"
  : > "$beta_file"

  betaseries_available=0
  if [[ -n "${betaseries_api_key:-}" ]]; then
    get-betaseries-member-id "$response_file"
    auth_status=$?
    if (( auth_status == 0 )); then
      betaseries_available=1
    elif (( auth_status == 1 )); then
      echo "$(msg beta_token_invalid)"
      if request-betaseries-token "$response_file" && get-betaseries-member-id "$response_file"; then
        betaseries_available=1
      else
        echo "$(msg beta_plex_only)" >&2
      fi
    else
      echo "$(msg beta_unreachable)" >&2
    fi
  else
    echo "$(msg beta_not_configured)"
  fi

  if (( betaseries_available )); then
    if http_code=$(curl --silent --show-error \
      --connect-timeout 10 \
      --max-time 30 \
      --get \
      --data-urlencode "id=$betaseries_member_id" \
      --output "$response_file" \
      --write-out '%{http_code}' \
      --header "X-BetaSeries-Key: $betaseries_api_key" \
      --header 'X-BetaSeries-Version: 3.0' \
      --header "Authorization: Bearer $betaseries_token" \
      --header "User-Agent: $script_name/1.0" \
      'https://api.betaseries.com/shows/member') &&
       [[ "$http_code" =~ ^2[0-9][0-9]$ ]] &&
       jq -e '.shows | type == "array"' "$response_file" >/dev/null 2>&1; then
      if ! jq -c '
        .shows[]? | {
          key: (if (.imdb_id // "") != "" then "imdb://\(.imdb_id)" elif (.thetvdb_id // 0) != 0 then "tvdb://\(.thetvdb_id)" else "title://\(.title | ascii_downcase)/\(.creation // 0)" end),
          title, year: (.creation // null), studio: null,
          tvdb_id: (if (.thetvdb_id // 0) != 0 then (.thetvdb_id | tostring) else null end),
          imdb_id: (if (.imdb_id // "") != "" then .imdb_id else null end),
          tmdb_id: null, source: "betaseries"
        }
      ' "$response_file" > "$beta_file"; then
        : > "$beta_file"
        echo "$(msg beta_invalid_response)" >&2
      else
        betaseries_count=$(wc -l < "$beta_file")
        echo -e "$ui_tag_ok $(msg beta_retrieved "$betaseries_count")"
      fi
    else
      echo "$(msg beta_retrieve_failed)" >&2
    fi
  fi

  mapfile -d '' -t plex_settings < <(
    plex_ip=""; plex_port=""; plex_token=""
    source "$plex_conf"
    printf '%s\0%s\0%s\0' "$plex_ip" "$plex_port" "$plex_token"
  )
  plex_ip=${plex_settings[0]:-localhost}
  plex_port=${plex_settings[1]:-32400}
  plex_token=${plex_settings[2]:-}
  [[ -n "$plex_token" ]] || { rm -rf "$temp_dir"; return 1; }
  plex_scheme=http
  [[ "$plex_ip" == https://* ]] && plex_scheme=https
  plex_host=${plex_ip#http://}; plex_host=${plex_host#https://}; plex_host=${plex_host%/}
  plex_base_url="$plex_scheme://$plex_host:$plex_port"

  if ! curl --silent --show-error --fail-with-body --connect-timeout 10 --max-time 30 \
    --output "$response_file" --header 'Accept: application/json' --header "X-Plex-Token: $plex_token" \
    "$plex_base_url/library/sections"; then
    rm -rf "$temp_dir"
    return 1
  fi
  plex_section_key=$(jq -r --arg section "$plex_section_series" '
    .MediaContainer.Directory[]? | select(.type == "show")
    | select((.key | tostring) == $section or .title == $section) | .key
  ' "$response_file")
  if [[ -z "$plex_section_key" || "$plex_section_key" == *$'\n'* ]]; then
    rm -rf "$temp_dir"
    return 1
  fi
  if ! curl --silent --show-error --fail-with-body --connect-timeout 10 --max-time 60 --get \
    --data-urlencode 'type=2' --data-urlencode 'includeGuids=1' \
    --output "$response_file" --header 'Accept: application/json' --header "X-Plex-Token: $plex_token" \
    "$plex_base_url/library/sections/$plex_section_key/all"; then
    rm -rf "$temp_dir"
    return 1
  fi
  if ! jq -e '.MediaContainer.Metadata // [] | type == "array"' "$response_file" >/dev/null 2>&1; then
    rm -rf "$temp_dir"
    return 1
  fi
  if ! jq -c '
    .MediaContainer.Metadata[]?
    | ([.Guid[]?.id | select(startswith("tvdb://"))][0] // null) as $tvdb
    | ([.Guid[]?.id | select(startswith("imdb://"))][0] // null) as $imdb
    | ([.Guid[]?.id | select(startswith("tmdb://"))][0] // null) as $tmdb
    | {key: ($imdb // $tvdb // $tmdb // "title://\(.title | ascii_downcase)/\(.year // 0)"),
       title, year: (.year // null), studio: (.studio // null),
       tvdb_id: ($tvdb | if . then sub("^tvdb://"; "") else null end),
       imdb_id: ($imdb | if . then sub("^imdb://"; "") else null end),
       tmdb_id: ($tmdb | if . then sub("^tmdb://"; "") else null end), source: "plex"}
  ' "$response_file" > "$plex_file"; then
    rm -rf "$temp_dir"
    return 1
  fi

  if ! jq --compact-output --slurp '
    group_by(.key)
    | map(
        . as $group
        | ($group | map(select(.source == "plex"))[0] // $group[0]) as $preferred
        | $preferred + {
            tvdb_id: ($group | map(.tvdb_id) | map(select(. != null))[0] // null),
            imdb_id: ($group | map(.imdb_id) | map(select(. != null))[0] // null),
            tmdb_id: ($group | map(.tmdb_id) | map(select(. != null))[0] // null)
          }
      )
    | sort_by(.title | ascii_downcase) | .[]
  ' "$beta_file" "$plex_file" > "$merged_file"; then
    rm -rf "$temp_dir"
    return 1
  fi
  if ! chmod 600 "$merged_file" || ! mv -f "$merged_file" "$destination"; then
    rm -rf "$temp_dir"
    return 1
  fi
  rm -rf "$temp_dir"
  return 0
}


#######################
## Check update
this_script=$(realpath -s "$0")
if curl -m 2 --head --silent --fail "$script_remote" 2>/dev/null >/dev/null; then
  md5_local=`md5sum "$this_script" | cut -f1 -d" " 2>/dev/null`
  md5_remote=`curl -s "$script_remote" | md5sum | cut -f1 -d" "`
  if [[ "$md5_local" != "$md5_remote" ]]; then
    echo -e "$ui_tag_warning $(msg new_version)"
  else
    echo -e "$ui_tag_ok $(msg up_to_date)"
  fi
else
  echo -e "$ui_tag_bad $(msg offline)"
fi
echo ""


#######################
## Dependencies
section_title="$(msg dependencies_title)"
printf "$ui_tag_section" "$(lon2 "$section_title")" "$section_title"
dependencies=( filebot awk wget xmlstarlet locate transmission-cli curl jq )
missing=()
available_dependencies=()
for dependency in "${dependencies[@]}"; do
  if command -v "$dependency" >/dev/null 2>&1; then
    available_dependencies+=("$dependency")
  else
    echo -e "$ui_tag_bad $(msg dependency_missing "$dependency")"
    echo -e "$ui_tag_warning $(msg dependency_installing)"
    echo $sudo | sudo -kS apt install $dependency -y 2>/dev/null
    if $dependency -help > /dev/null 2>/dev/null ; then
      available_dependencies+=("$dependency")
    else
      echo -e "$ui_tag_bad $(msg dependency_manual "$dependency")"
      missing+=("$dependency")
    fi                                                                                    ##
  fi
done
if ((${#available_dependencies[@]})); then
  dependencies_list=$(IFS=,; echo "${available_dependencies[*]}")
  dependencies_list="${dependencies_list//,/, }"
  echo -e "$ui_tag_ok $(msg dependencies_ok "$dependencies_list")"
fi
if ((${#missing[@]})); then
    echo "$(msg dependency_hint "${missing[*]}")"
    exit 1
fi
echo ""


#######################
## Get latest movies and series
section_title="$(msg download_title)"
printf "$ui_tag_section" $(lon2 "$section_title") "$section_title"
rss_movies_file="$script_folder/rss_movies.xml"
rss_series_file="$script_folder/rss_series.xml"
url_conf_file="$script_folder/url.conf"
url_conf_temp=$(mktemp "$script_tmp_folder/c411-url.XXXXXX.conf")
if ! wget -q -O "$url_conf_temp" "$url_conf_remote"; then
  rm -f "$url_conf_temp"
  echo -e "$ui_tag_bad $(msg url_config_failed "$url_conf_remote")"
  exit 1
fi
mv -f "$url_conf_temp" "$url_conf_file"
rss_movies_url_template=""
rss_series_url_template=""
while IFS= read -r url_conf_line; do
  if [[ "$url_conf_line" =~ ^[[:space:]]*rss_movies_url[[:space:]]*=(.*)$ ]]; then
    rss_movies_url_template="${BASH_REMATCH[1]}"
    rss_movies_url_template="${rss_movies_url_template#\"}"
    rss_movies_url_template="${rss_movies_url_template%\"}"
    rss_movies_url_template="${rss_movies_url_template#\'}"
    rss_movies_url_template="${rss_movies_url_template%\'}"
  elif [[ "$url_conf_line" =~ ^[[:space:]]*rss_series_url[[:space:]]*=(.*)$ ]]; then
    rss_series_url_template="${BASH_REMATCH[1]}"
    rss_series_url_template="${rss_series_url_template#\"}"
    rss_series_url_template="${rss_series_url_template%\"}"
    rss_series_url_template="${rss_series_url_template#\'}"
    rss_series_url_template="${rss_series_url_template%\'}"
  fi
done < "$url_conf_file"
rss_movies_url="${rss_movies_url_template//\$\{c411_api_key\}/$c411_api_key}"
rss_movies_url="${rss_movies_url//\$c411_api_key/$c411_api_key}"
rss_series_url="${rss_series_url_template//\$\{c411_api_key\}/$c411_api_key}"
rss_series_url="${rss_series_url//\$c411_api_key/$c411_api_key}"

download-rss() {
  local media_label="$1" rss_url="$2" destination="$3" rss_temp_file

  if [[ "$rss_url" != http://* && "$rss_url" != https://* ]]; then
    echo -e "$ui_tag_bad $(msg rss_invalid_url "$media_label" "$url_conf_remote")"
    return 1
  fi
  rss_temp_file=$(mktemp "$script_tmp_folder/c411-rss.XXXXXX.xml") || return 1
  if ! wget -q -O "$rss_temp_file" "$rss_url"; then
    rm -f "$rss_temp_file"
    echo -e "$ui_tag_bad $(msg rss_download_failed "$media_label")"
    return 1
  fi
  if ! xmlstarlet val -q "$rss_temp_file" 2>/dev/null ||
     [[ "$(xmlstarlet sel -t -v 'local-name(/*)' "$rss_temp_file" 2>/dev/null)" != "rss" ]]; then
    rm -f "$rss_temp_file"
    echo -e "$ui_tag_bad $(msg rss_invalid_response "$media_label")"
    return 1
  fi
  mv -f "$rss_temp_file" "$destination"
  echo -e "$ui_tag_ok $(msg rss_downloaded "$media_label")"
}

download-rss "$(msg media_movies)" "$rss_movies_url" "$rss_movies_file" || exit 1

series_enabled=1
if [[ -z "${plex_section_series:-}" ]]; then
  echo -e "$ui_tag_warning $(msg series_no_section)"
  series_enabled=0
elif [[ -z "${filebot_series:-}" || ! -d "$filebot_series" ]]; then
  echo -e "$ui_tag_warning $(msg series_no_destination)"
  series_enabled=0
elif ! download-rss "$(msg media_series)" "$rss_series_url" "$rss_series_file"; then
  echo -e "$ui_tag_warning $(msg series_no_rss)"
  series_enabled=0
fi

normalize-series-name() {
  local value="${1,,}"
  value=${value//œ/oe}
  value=${value//æ/ae}
  printf '%s' "$value" | sed 's/[^[:alnum:]]//g'
}

declare -A series_watchlist=()
declare -A series_tmdb_watchlist=()
declare -A series_imdb_watchlist=()
declare -A series_tvdb_watchlist=()
declare -A series_tmdb_to_tvdb=()
declare -A series_imdb_to_tvdb=()
declare -A series_title_ambiguous=()
if (( series_enabled )); then
  if ! generate-series-watchlist "$script_folder/series_watchlist.jsonl"; then
    echo -e "$ui_tag_warning $(msg series_list_failed)"
    series_enabled=0
  else
    while IFS=$'\x1f' read -r series_title watch_tvdb_id watch_tmdb_id watch_imdb_id; do
      series_key=$(normalize-series-name "$series_title")
      if [[ -n "$series_key" ]]; then
        if [[ -n "${series_watchlist[$series_key]:-}" ]]; then
          series_title_ambiguous[$series_key]=1
        else
          series_watchlist[$series_key]="$series_title"
        fi
      fi
      [[ "$watch_tvdb_id" =~ ^[0-9]+$ ]] && series_tvdb_watchlist[$watch_tvdb_id]="$series_title"
      [[ "$watch_tmdb_id" =~ ^[0-9]+$ ]] && series_tmdb_watchlist[$watch_tmdb_id]="$series_title"
      [[ "$watch_imdb_id" =~ ^tt[0-9]+$ ]] && series_imdb_watchlist[$watch_imdb_id]="$series_title"
      [[ "$watch_tvdb_id" =~ ^[0-9]+$ && "$watch_tmdb_id" =~ ^[0-9]+$ ]] && series_tmdb_to_tvdb[$watch_tmdb_id]="$watch_tvdb_id"
      [[ "$watch_tvdb_id" =~ ^[0-9]+$ && "$watch_imdb_id" =~ ^tt[0-9]+$ ]] && series_imdb_to_tvdb[$watch_imdb_id]="$watch_tvdb_id"
    done < <(jq -r '[.title, (.tvdb_id // ""), (.tmdb_id // ""), (.imdb_id // "")] | join("\u001f")' "$script_folder/series_watchlist.jsonl")
    if ((${#series_watchlist[@]} == 0)); then
      echo -e "$ui_tag_warning $(msg series_list_empty)"
      series_enabled=0
    fi
  fi
fi
if (( series_enabled )); then
  echo -e "$ui_tag_ok $(msg series_loaded "${#series_watchlist[@]}")"
fi
echo " ----------------------------------------------------------------------------"

current_processing_type=""
while IFS=$'\x1f' read -r media_type title guid enclosure_url tmdb_id imdb_id tvdb_id; do
  if [[ -z "$title" || -z "$guid" || "$enclosure_url" != http://* && "$enclosure_url" != https://* ]]; then
    echo -e "$ui_tag_bad $(msg invalid_rss_item "$(media-name "$media_type")")"
    continue
  fi
  if [[ "$media_type" != "$current_processing_type" ]]; then
    current_processing_type="$media_type"
    echo
    if [[ "$media_type" == "series" ]]; then
      section_title="$(msg processing_series)"
    else
      section_title="$(msg processing_movies)"
    fi
    printf "$ui_tag_section" "$(lon2 "$section_title")" "$section_title"
  fi
  if [[ "$media_type" == "series" ]]; then
    script_db_log="$script_db_series_log"
  else
    script_db_log="$script_db_movies_log"
  fi
  echo -e "$ui_tag_info $(msg title "$title")"
  echo -e "$ui_tag_info $(msg guid "$guid")"
  torrent_file="$script_folder/torrents/$guid.torrent"
  torrent_processed=0
  torrent_skipped=0
  rss_series_tvdb_id=""
  if [[ "$media_type" == "series" ]]; then
    if [[ "$tvdb_id" =~ ^[0-9]+$ ]]; then
      rss_series_tvdb_id="$tvdb_id"
    elif [[ "$tmdb_id" =~ ^[0-9]+$ && "${series_tmdb_to_tvdb[$tmdb_id]:-}" =~ ^[0-9]+$ ]]; then
      rss_series_tvdb_id=${series_tmdb_to_tvdb[$tmdb_id]}
    elif [[ "$imdb_id" =~ ^tt[0-9]+$ && "${series_imdb_to_tvdb[$imdb_id]:-}" =~ ^[0-9]+$ ]]; then
      rss_series_tvdb_id=${series_imdb_to_tvdb[$imdb_id]}
    fi
  fi
  
  ########################################
  ## Check db file
  if grep -Fxq "$guid" "$script_db_log"; then
    echo -e "$ui_tag_warning $(msg already_processed)"
    echo " ----------------------------------------------------------------------------"
    continue
  fi
  
  ########################################
  ## Skip torrent from title
  title_lower=${title,,}
  skip_list_sorted=$(echo "$skip_list" | tr '|' '\n' | tr '[:upper:]' '[:lower:]' | sort -u | xargs)
  for skip in $skip_list_sorted; do
    if [[ "$title_lower" == *"$skip"* ]]; then
      echo -e "$ui_tag_bad $(msg ignored_title "$skip")"
      torrent_skipped=1
      break
    fi
  done
  if (( torrent_skipped )); then
    if ! grep -Fxq "$guid" "$script_db_log"; then
      printf '%s\n' "$guid" >> "$script_db_log"
      echo -e "$ui_tag_processed $(msg db_added)"
    fi
    echo " ----------------------------------------------------------------------------"
    continue
  fi
  
  ########################################
  ## Téléchargement du fichier torrent
  if [[ ! -s "$torrent_file" ]]; then
    if wget -q "$enclosure_url" -O "$torrent_file"; then
      echo -e "$ui_tag_ok $(msg torrent_downloaded)"
    else
      echo -e "$ui_tag_bad $(msg torrent_download_failed)"
      rm -f "$torrent_file"
      echo " ----------------------------------------------------------------------------"
      continue
    fi
  fi
  
  ########################################
  ## Récupération du nom interne du torrent
  torrent_name=$(transmission-show "$torrent_file" | sed -nE 's/^[[:space:]]*Name:[[:space:]]*//p' | head -n 1)
  if [[ -z "$torrent_name" ]]; then
    echo -e "$ui_tag_bad $(msg torrent_name_failed)"
    echo " ----------------------------------------------------------------------------"
    continue
  fi
  
  ########################################
  ## Extraction de tous les fichiers vidéo acceptés
  mapfile -t new_files < <(transmission-show "$torrent_file" | sed -n '/FILES/,$p' | grep -Ei '\.(mkv|mp4|avi)([[:space:]]|$)' | sed 's/^[[:space:]]*//' | sed -E 's/\.(mkv|mp4|avi).*/.\1/I')
  if ((${#new_files[@]} == 0)); then
    echo -e "$ui_tag_bad $(msg no_video)"
    if ! grep -Fxq "$guid" "$script_db_log"; then
      printf '%s\n' "$guid" >> "$script_db_log"
      echo -e "$ui_tag_processed $(msg db_added)"
    fi
    echo " ----------------------------------------------------------------------------"
    continue
  fi

  ########################################
  ## Filtre des teams interdites
  if [[ -n "${banned_teams:-}" ]]; then
    banned_team=""
    for release_name in "${new_files[@]}" "$torrent_name" "$title"; do
      if banned_team=$(release_team_from_name "$(basename "$release_name")" "$banned_teams"); then
        break
      fi
    done
    if [[ -n "$banned_team" ]]; then
      echo -e "$ui_tag_bad $(msg banned_team "$banned_team")"
      if ! grep -Fxq "$guid" "$script_db_log"; then
        printf '%s\n' "$guid" >> "$script_db_log"
        echo -e "$ui_tag_processed $(msg db_added)"
      fi
      echo " ----------------------------------------------------------------------------"
      continue
    fi
  fi

  ########################################
  ## Filtre des teams autorisées
  if [[ -n "${approved_teams:-}" ]]; then
    approved_team=""
    for release_name in "${new_files[@]}" "$torrent_name" "$title"; do
      if approved_team=$(release_team_from_name "$(basename "$release_name")" "$approved_teams"); then
        break
      fi
    done
    if [[ -z "$approved_team" ]]; then
      echo -e "$ui_tag_bad $(msg team_not_approved "$approved_teams")"
      if ! grep -Fxq "$guid" "$script_db_log"; then
        printf '%s\n' "$guid" >> "$script_db_log"
        echo -e "$ui_tag_processed $(msg db_added)"
      fi
      echo " ----------------------------------------------------------------------------"
      continue
    fi
    echo -e "$ui_tag_ok $(msg approved_team "$approved_team")"
  fi
  
  ########################################
  ## Analyse de tous les fichiers vidéo
  accepted_files=()
  accepted_codecs=()
  accepted_movie_names=()
  accepted_movie_synopses=()
  accepted_imdb_ratings=()
  accepted_imdb_ids=()
  accepted_tmdb_ids=()
  accepted_tmdb_urls=()
  accepted_tvdb_ids=()
  accepted_tvdb_urls=()
  accepted_poster_urls=()
  accepted_media_types=()
  accepted_episode_keys=()
  for my_file_raw in "${new_files[@]}"; do
    my_file=$(basename "$my_file_raw")
    my_file_lower=${my_file,,}
    my_file_codec=$(detect-codec-from-name "$my_file_lower")
    if [[ "$my_file_codec" == "Unknown" ]]; then
      my_file_codec=$(detect-codec-from-name "$title_lower")
    fi
    echo -e "$ui_tag_ok $(msg file "$my_file")"
    
    ########################################
    ## Analyse FileBot
    temp_dir=$(mktemp -d "$script_tmp_folder/c411-filebot.XXXXXX")
    filebot_input_name="$my_file"
    if ((${#new_files[@]} == 1)) && [[ -n "${title//[[:space:]]/}" ]]; then
      filebot_input_name="${title//\// -}.${my_file##*.}"
      filebot_input_name="${filebot_input_name//\\/ -}"
    fi
    temp_file="$temp_dir/$filebot_input_name"
    touch "$temp_file"
    filebot_name_full=$(filebot --action test -script fn:amc -non-strict --conflict override --lang fr --encoding UTF-8 -rename "$temp_file" --def minFileSize=0 minLengthMS=0 seriesDB=TheTVDB --def 'seriesFormat=/SERIES/{n.replace("?", "").replace(":", "").replace("  ", " ")}/{n.replace("?", "").replace(":", "").replace("  ", " ")} - {sxe} - {t.replace("?", "").replace(":", "").replace("  ", " ")}' --def 'movieFormat=/MOVIE/{n.replace("?", "").replace(":", "").replace("  ", " ")} ({y})' --output "$temp_dir" 2>/dev/null | grep '\[TEST\]' | sed -n 's/^.* to \[\(.*\)\]$/\1/p' | head -n 1)

    filebot_retry_reason=""
    if [[ -z "$filebot_name_full" ]]; then
      filebot_retry_reason="name not found"
    elif [[ "$media_type" == "movie" && "$filebot_name_full" == */SERIES/* ]]; then
      filebot_retry_reason="incorrect TV series detection"
    elif [[ "$media_type" == "series" && "$filebot_name_full" == */MOVIE/* ]]; then
      filebot_retry_reason="incorrect movie detection"
    fi

    if [[ "$media_type" == "movie" && "$tmdb_id" =~ ^[0-9]+$ ]]; then
      if ((${#new_files[@]} == 1)); then
        echo -e "$ui_tag_info $(msg identify_movie "$tmdb_id")"
        forced_filebot_name_full=$(filebot -rename "$temp_file" --q "$tmdb_id" --db TheMovieDB --lang fr --encoding UTF-8 --action test --format '/MOVIE/{n.replace("?", "").replace(":", "").replace("  ", " ")} ({y})' --output "$temp_dir" 2>/dev/null | sed -n 's/^.* to \[\(.*\)\]$/\1/p' | head -n 1)
        if [[ "$forced_filebot_name_full" == */MOVIE/* ]]; then
          filebot_name_full="$forced_filebot_name_full"
          echo -e "$ui_tag_ok $(msg filebot_movie_found "$(basename "$filebot_name_full")")"
        else
          filebot_name_full=""
          echo -e "$ui_tag_bad $(msg filebot_movie_failed "$tmdb_id")"
        fi
      elif [[ -n "$filebot_retry_reason" ]]; then
        echo -e "$ui_tag_warning $(msg tmdb_multifile_skip)"
      fi
    elif [[ "$media_type" == "series" && "$rss_series_tvdb_id" =~ ^[0-9]+$ ]]; then
      echo -e "$ui_tag_info $(msg identify_series "$rss_series_tvdb_id")"
      forced_filebot_name_full=$(filebot -rename "$temp_file" --q "$rss_series_tvdb_id" --db TheTVDB --lang fr --encoding UTF-8 --action test --format '/SERIES/{n.replace("?", "").replace(":", "").replace("  ", " ")}/{n.replace("?", "").replace(":", "").replace("  ", " ")} - {sxe} - {t.replace("?", "").replace(":", "").replace("  ", " ")}' --output "$temp_dir" 2>/dev/null | sed -n 's/^.* to \[\(.*\)\]$/\1/p' | head -n 1)
      if [[ "$forced_filebot_name_full" == */SERIES/*/* ]]; then
        filebot_name_full="$forced_filebot_name_full"
        echo -e "$ui_tag_ok $(msg filebot_series_found "$(basename "$filebot_name_full")")"
      else
        echo -e "$ui_tag_warning $(msg filebot_series_failed "$rss_series_tvdb_id")"
      fi
    fi
    rm -rf "$temp_dir"

    if [[ -z "$filebot_name_full" ]]; then
      torrent_skipped=1
      echo -e "$ui_tag_bad $(msg filebot_no_name)"
      continue
    fi
    
    ########################################
    ## Media type and series watchlist
    if [[ "$media_type" == "series" ]]; then
      if [[ "$filebot_name_full" != */SERIES/*/* ]]; then
        echo -e "$ui_tag_bad $(msg filebot_not_series "$my_file")"
        torrent_skipped=1
        continue
      fi
      series_name=$(basename "$(dirname "$filebot_name_full")")
      series_key=$(normalize-series-name "$series_name")
      tracked_series_name=""
      if [[ "$rss_series_tvdb_id" =~ ^[0-9]+$ && -n "${series_tvdb_watchlist[$rss_series_tvdb_id]:-}" ]]; then
        tracked_series_name=${series_tvdb_watchlist[$rss_series_tvdb_id]}
      elif [[ "$tmdb_id" =~ ^[0-9]+$ && -n "${series_tmdb_watchlist[$tmdb_id]:-}" ]]; then
        tracked_series_name=${series_tmdb_watchlist[$tmdb_id]}
      elif [[ "$imdb_id" =~ ^tt[0-9]+$ && -n "${series_imdb_watchlist[$imdb_id]:-}" ]]; then
        tracked_series_name=${series_imdb_watchlist[$imdb_id]}
      elif [[ -n "$series_key" && -z "${series_title_ambiguous[$series_key]:-}" ]]; then
        tracked_series_name=${series_watchlist[$series_key]:-}
      fi
      if [[ -z "$tracked_series_name" ]]; then
        echo -e "$ui_tag_processed $(msg series_not_tracked "$series_name")"
        torrent_skipped=1
        continue
      fi
      echo -e "$ui_tag_ok $(msg series_tracked "$tracked_series_name")"
    else
      if [[ "$filebot_name_full" != */MOVIE/* ]]; then
        echo -e "$ui_tag_bad $(msg filebot_unknown_type)"
        torrent_skipped=1
        continue
      fi
      series_name=""
    fi
    filebot_name=$(basename "$filebot_name_full")
    echo -e "$ui_tag_ok $(msg filebot_name "$filebot_name")"
    
    ########################################
    ## Filtres
    if [[ ! "$my_file_lower $title_lower" =~ $resolution_pattern ]]; then
      echo -e "$ui_tag_bad $(msg resolution_ignored "$resolution_preference")"
      torrent_skipped=1
      continue
    fi
    skip_list_sorted=$(echo "$skip_list" | tr '|' '\n' | tr '[:upper:]' '[:lower:]' | sort -u | xargs)
    for skip in $skip_list_sorted; do
      if [[ "$my_file_lower" == *"$skip"* ]]; then
        echo -e "$ui_tag_bad $(msg release_ignored "$skip")"
        torrent_skipped=1
        continue 2
      fi
    done

    ########################################
    ## FileBot metadata and optional IMDb rating filter
    if [[ "$media_type" == "series" ]]; then
      movie_name="$series_name"
      movie_synopsis="$(msg series_episode)"
      movie_imdb_rating="$(msg unavailable)"
      movie_imdb_id="$imdb_id"
      [[ "$movie_imdb_id" =~ ^tt[0-9]+$ ]] || movie_imdb_id="$(msg unavailable)"
      movie_tmdb_id="$tmdb_id"
      if [[ "$movie_tmdb_id" =~ ^[0-9]+$ ]]; then
        movie_tmdb_url="https://www.themoviedb.org/tv/$movie_tmdb_id?language=fr-FR"
      else
        movie_tmdb_id="$(msg unavailable)"
        movie_tmdb_url=""
      fi
      if [[ "$rss_series_tvdb_id" =~ ^[0-9]+$ ]]; then
        get-series-metadata "$rss_series_tvdb_id"
      else
        get-series-metadata "$series_name"
      fi
      if [[ "$filebot_name" =~ [[:space:]]-[[:space:]]([0-9]+[xX][0-9]+([-+][0-9]+)*)[[:space:]]-[[:space:]] ]]; then
        episode_key=${BASH_REMATCH[1],,}
      else
        episode_key=$(printf '%s' "${series_name,,}|${filebot_name,,}" | md5sum | cut -d' ' -f1)
      fi
    else
      movie_name="${filebot_name%.*}"
      episode_key=""
      series_tvdb_id=""
      series_tvdb_url=""
      get-movie-metadata "$movie_name" "$tmdb_id"
    fi
    if [[ "$media_type" == "movie" && -n "$imdb_minimum" ]]; then
      if [[ ! "$movie_imdb_rating" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        echo -e "$ui_tag_bad $(msg imdb_unavailable "$imdb_minimum")"
        torrent_skipped=1
        continue
      elif ! imdb-rating-meets-minimum "$movie_imdb_rating" "$imdb_minimum"; then
        echo -e "$ui_tag_bad $(msg imdb_ignored "$movie_imdb_rating" "$imdb_minimum")"
        torrent_skipped=1
        continue
      else
        echo -e "$ui_tag_ok $(msg imdb_accepted "$movie_imdb_rating" "$imdb_minimum")"
      fi
    elif [[ "$media_type" == "movie" ]]; then
      echo -e "$ui_tag_info $(msg imdb_rating "$movie_imdb_rating")"
    fi
    
    ########################################
    ## Checking for the presence of a local file
    local_search_names=("$filebot_name")
    local_search_prefix=0
    if [[ "$media_type" == "series" ]]; then
      local_search_names=("$series_name - $episode_key")
      local_tracked_series_name=${tracked_series_name//\?/}
      local_tracked_series_name=${local_tracked_series_name//:/}
      while [[ "$local_tracked_series_name" == *"  "* ]]; do
        local_tracked_series_name=${local_tracked_series_name//  / }
      done
      if [[ -n "$local_tracked_series_name" && "$local_tracked_series_name" != "$series_name" ]]; then
        local_search_names+=("$local_tracked_series_name - $episode_key")
      fi
      local_search_prefix=1
    elif [[ "$tmdb_id" =~ ^[0-9]+$ ]]; then
      english_local_name=$(filebot -list --q "$tmdb_id" --db TheMovieDB --lang en \
        --filter "id == $tmdb_id" \
        --format '{n.replace("?", "").replace(":", "").replace("  ", " ")} ({y})' \
        --log OFF 2>/dev/null | head -n 1)
      if [[ -n "$english_local_name" ]]; then
        english_local_name="${english_local_name}.${filebot_name##*.}"
        [[ "$english_local_name" == "$filebot_name" ]] || local_search_names+=("$english_local_name")
      fi
    fi
    if [[ -n "${plex_sort_folder:-}" ]]; then
      mapfile -t locate_databases < <(find "$plex_sort_folder" -maxdepth 1 -type f -name "*.locate.db" | sort)
      local_check=""
      for locate_db in "${locate_databases[@]}"; do
        for local_search_name in "${local_search_names[@]}"; do
          local_check+=$'\n'"$(locate -i -d "$locate_db" -- "$local_search_name" 2>/dev/null | awk -v expected="$local_search_name" -v prefix="$local_search_prefix" '
            { name = $0; sub(/^.*\//, "", name); if ((!prefix && tolower(name) == tolower(expected)) || (prefix && index(tolower(name), tolower(expected " - ")) == 1)) print }
          ' || true)"
        done
      done
      local_check=$(printf '%s\n' "$local_check" | sed '/^$/d')
    else
      local_check=""
      for local_search_name in "${local_search_names[@]}"; do
        local_check+=$'\n'"$(locate -i -- "$local_search_name" 2>/dev/null | grep -viE '/mnt/Plex/|/\.Trash/' | awk -v expected="$local_search_name" -v prefix="$local_search_prefix" '
          { name = $0; sub(/^.*\//, "", name); if ((!prefix && tolower(name) == tolower(expected)) || (prefix && index(tolower(name), tolower(expected " - ")) == 1)) print }
        ' || true)"
      done
      local_check=$(printf '%s\n' "$local_check" | sed '/^$/d')
    fi
    if [[ -n "$local_check" ]]; then
      local_check_file=$(printf '%s\n' "$local_check" | head -n 1)
      local_check_width=$(mediainfo --Inform="Video;%Width%" "$local_check_file")
      local_check_height=$(mediainfo --Inform="Video;%Height%" "$local_check_file")
      local_check_standard_resolution=$(resolution-standard "$local_check_width" "$local_check_height")
      local_check_codec_raw=$(mediainfo --Inform="Video;%Format%" "$local_check_file")
      local_check_codec=$(codec-standard "$local_check_codec_raw")
      echo -e "$ui_tag_processed $(msg local_found "$(media-name "$media_type")" "$local_check_file")"
      echo -e "$ui_tag_processed $(msg local_resolution "$local_check_standard_resolution")"
      echo -e "$ui_tag_processed $(msg local_codec "$local_check_codec")"

      local_resolution_rank=$(resolution-rank "$local_check_standard_resolution")
      target_resolution_rank=$(resolution-rank "$resolution_target_standard")
      if (( local_resolution_rank >= 0 && local_resolution_rank < target_resolution_rank )); then
        echo -e "$ui_tag_ok $(msg resolution_upgrade "$local_check_standard_resolution" "$resolution_target_standard")"
      elif (( local_resolution_rank > target_resolution_rank )); then
        echo -e "$ui_tag_processed $(msg resolution_downgrade "$local_check_standard_resolution" "$resolution_target_standard")"
        torrent_skipped=1
        continue
      elif [[ "$my_file_codec" == "$local_check_codec" ]]; then
        echo -e "$ui_tag_processed $(msg same_codec "$local_check_codec")"
        torrent_skipped=1
        continue
      elif [[ -n "${codec_preference:-}" && "$my_file_codec" == "$codec_preference" ]]; then
        echo -e "$ui_tag_ok $(msg codec_replacement_preferred "$local_check_codec" "$my_file_codec" "$codec_preference")"
      elif [[ -n "${codec_preference:-}" ]]; then
        echo -e "$ui_tag_processed $(msg codec_ignored "$my_file_codec" "$codec_preference")"
        torrent_skipped=1
        continue
      else
        echo -e "$ui_tag_ok $(msg codec_replacement "$local_check_codec" "$my_file_codec")"
      fi
    else
      echo -e "$ui_tag_ok $(msg no_local "$(media-name "$media_type")" "$my_file_codec")"
    fi
    echo -e "$ui_tag_ok $(msg new_media "$(media-name "$media_type")")"
    
    accepted_files+=("$my_file_raw")
    accepted_codecs+=("$my_file_codec")
    accepted_movie_names+=("$movie_name")
    accepted_movie_synopses+=("$movie_synopsis")
    accepted_imdb_ratings+=("$movie_imdb_rating")
    accepted_imdb_ids+=("$movie_imdb_id")
    accepted_tmdb_ids+=("$movie_tmdb_id")
    accepted_tmdb_urls+=("$movie_tmdb_url")
    accepted_tvdb_ids+=("$series_tvdb_id")
    accepted_tvdb_urls+=("$series_tvdb_url")
    accepted_poster_urls+=("$movie_poster_url")
    accepted_media_types+=("$media_type")
    accepted_episode_keys+=("$episode_key")
  done
  
  ########################################
  ## Aucun fichier accepté
  if ((${#accepted_files[@]} == 0)); then
    echo -e "$ui_tag_bad $(msg no_accepted_video)"
    if (( torrent_skipped )); then
      if ! grep -Fxq "$guid" "$script_db_log"; then
        printf '%s\n' "$guid" >> "$script_db_log"
        echo -e "$ui_tag_processed $(msg db_added)"
      fi
    fi
    echo " ----------------------------------------------------------------------------"
    continue
  fi
  #echo -e "$ui_tag_ok Accepted files: ${#accepted_files[@]}"
  transmission_host="$transmission_ip:$transmission_port"
  transmission_auth="$transmission_login:$transmission_password"
  
  ########################################
  ## Recherche d’un torrent déjà présent
  torrent_id=$(transmission-remote "$transmission_host" -n "$transmission_auth" -l | grep -F -- "$torrent_name" | head -n 1 | awk '{print $1}')
  if [[ -n "$torrent_id" ]]; then
    echo -e "$ui_tag_warning $(msg torrent_present "$torrent_id")"
    # Aucun fichier n’est désactivé ou réactivé sur un torrent existant.
    torrent_processed=1
  else
    ########################################
    ## Destination
    torrent_media_type=${accepted_media_types[0]}
    torrent_codec="Unknown"
    for accepted_codec in "${accepted_codecs[@]}"; do
      if [[ "$torrent_media_type" == "series" ]]; then
        if [[ "$torrent_codec" == "Unknown" ]]; then
          torrent_codec="$accepted_codec"
        elif [[ "$accepted_codec" != "$torrent_codec" ]]; then
          torrent_codec="Mixed"
          break
        fi
      elif [[ "$accepted_codec" == "H265" ]]; then
        torrent_codec="H265"
        break
      elif [[ "$torrent_codec" == "Unknown" ]]; then
        torrent_codec="$accepted_codec"
      fi
    done

    if [[ "$torrent_media_type" == "series" ]]; then
      if [[ "$torrent_codec" == "H265" && -n "${filebot_series_H265:-}" && -d "$filebot_series_H265" ]]; then
        transmission_folder="$filebot_series_H265"
      else
        transmission_folder="$filebot_series"
      fi
    elif [[ "$torrent_codec" == "H265" && -n "${filebot_films_H265:-}" && -d "$filebot_films_H265" ]]; then
      transmission_folder="$filebot_films_H265"
    elif [[ "$torrent_codec" == "AV1" && -n "${filebot_films_AV1:-}" && -d "$filebot_films_AV1" ]]; then
      transmission_folder="$filebot_films_AV1"
    else
      transmission_folder="$filebot_films"
    fi
    echo -e "$ui_tag_info $(msg torrent_codec "$torrent_codec")"
    echo -e "$ui_tag_info $(msg destination "$transmission_folder")"

    ########################################
    ## Resolve movie identities and codec duplicates already in Transmission
    torrent_movie_labels=()
    accepted_identity_labels=()
    for accepted_index in "${!accepted_files[@]}"; do
      movie_identity_found=0
      if [[ "${accepted_media_types[$accepted_index]}" == "series" ]]; then
        episode_key=${accepted_episode_keys[$accepted_index]}
        if [[ "${accepted_tmdb_ids[$accepted_index]}" =~ ^[0-9]+$ ]]; then
          movie_label="c411-series-tmdb-${accepted_tmdb_ids[$accepted_index]}-$episode_key"
          movie_identity_found=1
        elif [[ "${accepted_imdb_ids[$accepted_index]}" =~ ^tt[0-9]+$ ]]; then
          movie_label="c411-series-imdb-${accepted_imdb_ids[$accepted_index]}-$episode_key"
          movie_identity_found=1
        else
          series_key=$(printf '%s' "${accepted_movie_names[$accepted_index],,}|$episode_key" | md5sum | cut -d' ' -f1)
          movie_label="c411-series-$series_key"
          movie_identity_found=1
        fi
        if [[ ! " ${torrent_movie_labels[*]} " == *" $movie_label "* ]]; then
          torrent_movie_labels+=("$movie_label")
        fi
        accepted_identity_labels[$accepted_index]="$movie_label"
      elif [[ "${accepted_tmdb_ids[$accepted_index]}" =~ ^[0-9]+$ ]]; then
        movie_label="c411-tmdb-${accepted_tmdb_ids[$accepted_index]}"
        if [[ ! " ${torrent_movie_labels[*]} " == *" $movie_label "* ]]; then
          torrent_movie_labels+=("$movie_label")
        fi
        movie_identity_found=1
      fi
      if [[ "${accepted_media_types[$accepted_index]}" != "series" && "${accepted_imdb_ids[$accepted_index]}" =~ ^tt[0-9]+$ ]]; then
        movie_label="c411-imdb-${accepted_imdb_ids[$accepted_index]}"
        if [[ ! " ${torrent_movie_labels[*]} " == *" $movie_label "* ]]; then
          torrent_movie_labels+=("$movie_label")
        fi
        movie_identity_found=1
      fi
      if (( ! movie_identity_found )); then
        movie_key=$(printf '%s' "${accepted_movie_names[$accepted_index],,}" | md5sum | cut -d' ' -f1)
        movie_label="c411-movie-$movie_key"
        if [[ ! " ${torrent_movie_labels[*]} " == *" $movie_label "* ]]; then
          torrent_movie_labels+=("$movie_label")
        fi
      fi
    done

    skip_codec_duplicate=0
    duplicate_hashes_to_stop=()
    duplicate_names_to_stop=()
    duplicate_completed_to_stop=()
    transmission_torrents=$(transmission-remote "$transmission_host" -n "$transmission_auth" -j -t all -i 2>/dev/null)
    if ! jq -e '.result == "success" and (.arguments.torrents | type == "array")' >/dev/null 2>&1 <<< "$transmission_torrents"; then
      echo -e "$ui_tag_bad $(msg transmission_inspect_failed)"
      echo " ----------------------------------------------------------------------------"
      continue
    fi
    if [[ "$torrent_media_type" == "series" && ${#accepted_files[@]} -gt 1 ]]; then
      echo -e "$ui_tag_info $(msg multifile_duplicate_skip)"
    else
      for movie_label in "${torrent_movie_labels[@]}"; do
        while IFS=$'\t' read -r existing_id existing_hash existing_name existing_codec existing_completed existing_series_label_count; do
        [[ -n "$existing_id" ]] || continue
        if [[ "$torrent_media_type" == "series" && "$existing_series_label_count" -gt 1 ]]; then
          echo -e "$ui_tag_processed $(msg episode_multifile "$existing_name")"
          skip_codec_duplicate=1
          break 2
        elif [[ -n "$codec_preference" && "$torrent_codec" == "$codec_preference" && "$existing_codec" != "$codec_preference" ]]; then
          if [[ ! " ${duplicate_hashes_to_stop[*]} " == *" $existing_hash "* ]]; then
            duplicate_hashes_to_stop+=("$existing_hash")
            duplicate_names_to_stop+=("$existing_name")
            duplicate_completed_to_stop+=("$existing_completed")
          fi
        else
          echo -e "$ui_tag_processed $(msg codec_duplicate "$torrent_codec" "$existing_name" "$existing_codec")"
          skip_codec_duplicate=1
          break 2
        fi
      done < <(
        jq -r --arg movie_label "$movie_label" '
          .arguments.torrents[] |
          select((.labels // []) | index($movie_label)) |
          [
            .id,
            .hashString,
            .name,
            (((.labels // []) | map(select(startswith("c411-codec-"))) | first // "Unknown") | sub("^c411-codec-"; "")),
            (if ((.sizeWhenDone // 0) > 0 and (.leftUntilDone // -1) == 0) then "yes" else "no" end),
            ((.labels // []) | map(select(startswith("c411-series-"))) | length)
          ] | @tsv
        ' <<< "$transmission_torrents"
        )
      done
    fi
    if (( skip_codec_duplicate )); then
      if ! grep -Fxq "$guid" "$script_db_log"; then
        printf '%s\n' "$guid" >> "$script_db_log"
        echo -e "$ui_tag_processed $(msg db_added)"
      fi
      echo " ----------------------------------------------------------------------------"
      continue
    fi
    
    ########################################
    ## Ajout en pause
    if ! transmission-remote "$transmission_host" -n "$transmission_auth" -a "$torrent_file" -w "$transmission_folder" -S >/dev/null 2>&1; then
      echo -e "$ui_tag_bad $(msg torrent_add_failed)"
      echo " ----------------------------------------------------------------------------"
      continue
    fi
    echo -e "$ui_tag_ok $(msg torrent_added)"
    sleep 1
    
    ########################################
    ## Récupération de l’ID numérique
    torrent_id=$(transmission-remote "$transmission_host" -n "$transmission_auth" -l | grep -F -- "$torrent_name" | head -n 1 | awk '{print $1}')
    if [[ -z "$torrent_id" ]]; then
      echo -e "$ui_tag_bad $(msg torrent_id_failed)"
      echo " ----------------------------------------------------------------------------"
      continue
    fi
    #echo -e "$ui_tag_ok Torrent ID: $torrent_id"

    if [[ "$torrent_media_type" != "series" ]]; then
      torrent_labels=("c411" "c411-codec-$torrent_codec" "${torrent_movie_labels[@]}")
      torrent_label_list=$(IFS=,; echo "${torrent_labels[*]}")
      if ! transmission-remote "$transmission_host" -n "$transmission_auth" -t "$torrent_id" -L "$torrent_label_list" >/dev/null 2>&1; then
        echo -e "$ui_tag_bad $(msg label_failed)"
        transmission-remote "$transmission_host" -n "$transmission_auth" -t "$torrent_id" -r >/dev/null 2>&1
        echo " ----------------------------------------------------------------------------"
        continue
      fi
    fi
    
    ########################################
    ## Liste des fichiers côté Transmission
    transmission_files=$(transmission-remote "$transmission_host" -n "$transmission_auth" -t "$torrent_id" -f)
    accepted_file_ids=()
    enabled_files=()
    enabled_movie_names=()
    enabled_movie_synopses=()
    enabled_imdb_ratings=()
    enabled_imdb_ids=()
    enabled_tmdb_ids=()
    enabled_tmdb_urls=()
    enabled_tvdb_ids=()
    enabled_tvdb_urls=()
    enabled_poster_urls=()
    enabled_media_types=()
    enabled_identity_labels=()
    for accepted_index in "${!accepted_files[@]}"; do
      accepted_file="${accepted_files[$accepted_index]}"
      accepted_name=$(basename "$accepted_file")
      file_id=$(printf '%s\n' "$transmission_files" | grep -E '^[[:space:]]*[0-9]+:' | grep -iF -- "$accepted_file" | head -n 1 | cut -d: -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      # Si le chemin complet ne correspond pas, essaie avec
      # seulement le nom du fichier.
      if [[ -z "$file_id" ]]; then
        file_id=$(printf '%s\n' "$transmission_files" | grep -E '^[[:space:]]*[0-9]+:' | grep -iF -- "$accepted_name" | head -n 1 | cut -d: -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      fi
      if [[ "$file_id" =~ ^[0-9]+$ ]]; then
#        echo -e "$ui_tag_ok File index $file_id: $accepted_name"
        accepted_file_ids+=("$file_id")
        enabled_files+=("$accepted_file")
        enabled_movie_names+=("${accepted_movie_names[$accepted_index]}")
        enabled_movie_synopses+=("${accepted_movie_synopses[$accepted_index]}")
        enabled_imdb_ratings+=("${accepted_imdb_ratings[$accepted_index]}")
        enabled_imdb_ids+=("${accepted_imdb_ids[$accepted_index]}")
        enabled_tmdb_ids+=("${accepted_tmdb_ids[$accepted_index]}")
        enabled_tmdb_urls+=("${accepted_tmdb_urls[$accepted_index]}")
        enabled_tvdb_ids+=("${accepted_tvdb_ids[$accepted_index]}")
        enabled_tvdb_urls+=("${accepted_tvdb_urls[$accepted_index]}")
        enabled_poster_urls+=("${accepted_poster_urls[$accepted_index]}")
        enabled_media_types+=("${accepted_media_types[$accepted_index]}")
        if [[ -n "${accepted_identity_labels[$accepted_index]:-}" ]]; then
          enabled_identity_labels+=("${accepted_identity_labels[$accepted_index]}")
        fi
#      else
#        echo -e "$ui_tag_bad File index not found: $accepted_name"
      fi
    done
    
    ########################################
    ## No accepted file index found : Transmission file deleted 
    if ((${#accepted_file_ids[@]} == 0)); then
      echo -e "$ui_tag_bad $(msg file_index_failed)"
      transmission-remote "$transmission_host" -n "$transmission_auth" -t "$torrent_id" -r >/dev/null 2>&1
      echo " ----------------------------------------------------------------------------"
      continue
    fi

    if [[ "$torrent_media_type" == "series" ]]; then
      torrent_labels=("c411" "c411-codec-$torrent_codec" "${enabled_identity_labels[@]}")
      torrent_label_list=$(IFS=,; echo "${torrent_labels[*]}")
      if ! transmission-remote "$transmission_host" -n "$transmission_auth" -t "$torrent_id" -L "$torrent_label_list" >/dev/null 2>&1; then
        echo -e "$ui_tag_bad $(msg series_label_failed)"
        transmission-remote "$transmission_host" -n "$transmission_auth" -t "$torrent_id" -r >/dev/null 2>&1
        echo " ----------------------------------------------------------------------------"
        continue
      fi
    fi
    
    ########################################
    ## Keep accepted files enabled and disable only unnecessary files
    file_ids=$(IFS=,; echo "${accepted_file_ids[*]}")
    echo -e "$ui_tag_info $(msg enabled_indexes "$file_ids")"

    mapfile -t all_file_ids < <(printf '%s\n' "$transmission_files" | awk '/^[[:space:]]*[0-9]+:/ { id=$1; sub(/:$/, "", id); print id }')
    disabled_file_ids=()
    for current_file_id in "${all_file_ids[@]}"; do
      file_is_accepted=0
      for accepted_file_id in "${accepted_file_ids[@]}"; do
        if [[ "$current_file_id" == "$accepted_file_id" ]]; then
          file_is_accepted=1
          break
        fi
      done
      if (( ! file_is_accepted )); then
        disabled_file_ids+=("$current_file_id")
      fi
    done

    if ((${#disabled_file_ids[@]})); then
      disabled_ids=$(IFS=,; echo "${disabled_file_ids[*]}")
      if transmission-remote "$transmission_host" -n "$transmission_auth" -t "$torrent_id" -G "$disabled_ids" >/dev/null 2>&1; then
        echo -e "$ui_tag_ok $(msg disabled_indexes "$disabled_ids")"
      else
        echo -e "$ui_tag_bad $(msg disable_indexes_failed "$disabled_ids")"
        transmission-remote "$transmission_host" -n "$transmission_auth" -t "$torrent_id" -r >/dev/null 2>&1
        echo " ----------------------------------------------------------------------------"
        continue
      fi
    fi

    duplicate_stop_failed=0
    for duplicate_index in "${!duplicate_hashes_to_stop[@]}"; do
      if transmission-remote "$transmission_host" -n "$transmission_auth" -t "${duplicate_hashes_to_stop[$duplicate_index]}" -S >/dev/null 2>&1; then
        echo -e "$ui_tag_warning $(msg duplicate_stopped "${duplicate_names_to_stop[$duplicate_index]}")"
        if [[ "${duplicate_completed_to_stop[$duplicate_index]}" == "yes" ]]; then
          echo -e "$ui_tag_processed $(msg completed_push_skip)"
        elif [[ -n "${push_token_app:-}" && -n "${push_target:-}" ]]; then
          push_content=$(render-stopped-push-notification "${duplicate_names_to_stop[$duplicate_index]}")
          if push-message "$(msg stopped_push_title)" "$push_content" "-1"; then
            echo -e "$ui_tag_ok $(msg stopped_push_sent "${duplicate_names_to_stop[$duplicate_index]}")"
          else
            echo -e "$ui_tag_bad $(msg stopped_push_failed "${duplicate_names_to_stop[$duplicate_index]}")"
          fi
        fi
      else
        echo -e "$ui_tag_bad $(msg duplicate_stop_failed "${duplicate_names_to_stop[$duplicate_index]}")"
        duplicate_stop_failed=1
      fi
    done
    if (( duplicate_stop_failed )); then
      transmission-remote "$transmission_host" -n "$transmission_auth" -t "$torrent_id" -r >/dev/null 2>&1
      echo " ----------------------------------------------------------------------------"
      continue
    fi
    
    ########################################
    ## Starting torrent
    if [[ "$transmission_torrent_paused" == "yes" ]]; then
      echo -e "$ui_tag_warning $(msg download_paused)"
      transmission_state="$(msg state_paused)"
      torrent_processed=1
    else
     if transmission-remote "$transmission_host" -n "$transmission_auth" -t "$torrent_id" -s >/dev/null 2>&1; then
        echo -e "$ui_tag_ok $(msg download_started)"
        for enabled_file in "${enabled_files[@]}"; do
          echo -e "$ui_tag_ok $(msg enabled "$(basename "$enabled_file")")"
        done
        transmission_state="$(msg state_started)"
        torrent_processed=1
      else
        echo -e "$ui_tag_bad $(msg torrent_start_failed)"
      fi
    fi

    if (( torrent_processed )) && [[ -n "${push_token_app:-}" && -n "${push_target:-}" ]]; then
      for enabled_index in "${!enabled_files[@]}"; do
        enabled_file="${enabled_files[$enabled_index]}"
        enabled_name=$(basename "$enabled_file")
        movie_name="${enabled_movie_names[$enabled_index]}"
        movie_synopsis="${enabled_movie_synopses[$enabled_index]}"
        imdb_rating="${enabled_imdb_ratings[$enabled_index]}"
        movie_imdb_id="${enabled_imdb_ids[$enabled_index]}"
        movie_tmdb_id="${enabled_tmdb_ids[$enabled_index]}"
        movie_tmdb_url="${enabled_tmdb_urls[$enabled_index]}"
        series_tvdb_id="${enabled_tvdb_ids[$enabled_index]}"
        series_tvdb_url="${enabled_tvdb_urls[$enabled_index]}"
        movie_poster_url="${enabled_poster_urls[$enabled_index]}"
        enabled_media_type="${enabled_media_types[$enabled_index]}"
        if [[ "$enabled_media_type" == "series" ]]; then
          push_content=$(render-push-notification "$push_notification_serie_added")
          push_url="$series_tvdb_url"
          push_url_title="$(msg view_tvdb)"
        else
          push_content=$(render-push-notification "$push_notification_movie_added")
          push_url="$movie_tmdb_url"
          push_url_title="$(msg view_tmdb)"
        fi
        poster_file=""
        if [[ -n "$movie_poster_url" ]]; then
          poster_file=$(mktemp "$script_tmp_folder/c411-poster.XXXXXX")
          if ! curl --silent --show-error --fail --location --max-time 20 --output "$poster_file" "$movie_poster_url"; then
            echo -e "$ui_tag_warning $(msg poster_failed "$movie_name")"
            rm -f "$poster_file"
            poster_file=""
          elif (( $(stat -c %s "$poster_file") > 5242880 )); then
            echo -e "$ui_tag_warning $(msg poster_too_large "$movie_name")"
            rm -f "$poster_file"
            poster_file=""
          fi
        fi
        if push-message "$(msg file_added_title)" "$push_content" "-1" "$push_url" "$push_url_title" "$poster_file"; then
          echo -e "$ui_tag_ok $(msg push_sent "$enabled_name")"
        else
          echo -e "$ui_tag_bad $(msg push_failed "$enabled_name")"
        fi
        [[ -n "$poster_file" ]] && rm -f "$poster_file"
      done
    fi
  fi
  
  ########################################
  ## Add GUID to db file
  if (( torrent_processed )); then
    if ! grep -Fxq "$guid" "$script_db_log"; then
      printf '%s\n' "$guid" >> "$script_db_log"
      echo -e "$ui_tag_processed $(msg db_added)"
    fi
  fi
  echo " ----------------------------------------------------------------------------"
done < <(
  for rss_media_type in movie series; do
    if [[ "$rss_media_type" == "series" ]]; then
      (( series_enabled )) || continue
      current_rss_file="$rss_series_file"
    else
      current_rss_file="$rss_movies_file"
    fi
    xmlstarlet sel \
      -N 'torznab=http://torznab.com/schemas/2015/feed' \
      -T \
      -t \
      -m '/rss/channel/item' \
      -o "$rss_media_type" \
      -o $'\x1f' \
      -v 'normalize-space(title)' \
      -o $'\x1f' \
      -v 'normalize-space(guid)' \
      -o $'\x1f' \
      -v 'enclosure/@url' \
      -o $'\x1f' \
      -v 'torznab:attr[@name="tmdbid"]/@value' \
      -o $'\x1f' \
      -v 'torznab:attr[@name="imdbid"]/@value' \
      -o $'\x1f' \
      -v 'torznab:attr[@name="tvdbid"]/@value' \
      -n \
      "$current_rss_file"
  done
)
