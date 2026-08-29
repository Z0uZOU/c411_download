#!/bin/bash

#######################
## Check if this script is running
lock_file="/tmp/$(basename "$0").lock"
exec 200>"$lock_file"

if ! flock -n 200; then
    echo "Script already running..."
    exit 1
fi


#######################
## Generating script variables and basics
script_name=$(basename "$0" | cut -d'.' -f1)
script_name_cap=${script_name^^}
script_name_full=$(basename "$0")
script_bin="$0"
script_conf=`echo $HOME"/.config/"$script_name"/"$script_name".conf"`
script_remote="https://raw.githubusercontent.com/Z0uZOU/$script_name/main/$script_name_full"
script_cron_log=`echo "/var/log/"$script_name".log"`
script_folder="$HOME/.config/$script_name"
script_db_movies_log="$script_folder/db_movies.log"
if [[ ! -d "$script_folder" ]]; then
  mkdir -p "$script_folder"
fi
if [[ ! -d "$script_folder/logs" ]]; then
  mkdir -p "$script_folder/logs"
fi
if [[ ! -d "$script_folder/torrents" ]]; then
  mkdir -p "$script_folder/torrents"
fi
if [[ ! -f "$script_db_movies_log" ]]; then
  touch "$script_db_movies_log"
fi

#######################
## Advanced command arguments
die() { echo "$*" >&2; exit 2; }  # complain to STDERR and exit with error
needs_arg() { if [ -z "$OPTARG" ]; then die "No arg for --$OPT option"; fi; }

while getopts eushf:cm:l:-: OPT; do
  # support long options: https://stackoverflow.com/a/28466267/519360
  if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
    OPT="${OPTARG%%=*}"       # extract long option name
    OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
    OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
  fi
  case "$OPT" in
    h | help )
            echo -e "\033[1m$script_name_cap - help\033[0m"
            echo ""
            echo "Usage : $script_bin [option]"
            echo ""
            echo "Available options:"
            echo "[value*] means optional argument"
            echo ""
            echo " -h or --help                              : this help menu"
            echo " -u or --update                            : update this script"
            echo " -m [value] or --mode=[value]              : change display mode (full)"
            echo " -l [value] or --language=[value]          : override language (fr or en)"
            echo " -c or --cron-log                          : display latest cron log"
            echo " -e [value*] or --edit-config=[value*]     : edit config file (default: nano)"
            echo " -s [value*] or --status=[value*]          : status/enable/disable the script"
            echo " -f \"[value]\" or --find=\"[value]\"          : find something in the logs"
            exit 0
            ;;
    f | find )
            needs_arg
            arg_search_value="$OPTARG"
            echo -e "\033[1m$script_name_cap - find feature\033[0m"
            echo "This feature require root privileges"
            echo ""
            echo "Checking for root privileges..."
            source "$script_conf" 2>/dev/null
            if [[ "$sudo" == "" ]] && [[ "$EUID" != "0" ]]; then
              echo "No root privileges... exit"
            else
              echo "Root privileges granted"
            fi
            echo "Updating db..."
            echo "$sudo" | sudo -kS updatedb 2>/dev/null
            logs_path=`echo "$sudo" | sudo -kS locate -r "/$script_name/logs$" 2>/dev/null`
            echo "Searching..."
            for log_path in $logs_path ; do
              my_logs=( `echo "$sudo" | sudo -kS find $log_path -type f 2>/dev/null` )
              for my_log in ${my_logs[@]} ; do
                echo "$sudo" | sudo -kS grep -Hin "$arg_search_value" $my_log 2>/dev/null
              done
            done
            exit 0
            ;;
    u | update )
            echo -e "\033[1m$script_name_cap - Update initiated\033[0m"
            read -n 1 -p "Do you want to proceed [y/N]:" yn
            printf "\r                                                     "
            if [[ "${yn}" == @(y|Y) ]]; then
              echo ""
              this_script=$(realpath -s "$0")
              echo "Script location : "$this_script
              if curl -m 2 --head --silent --fail "$script_remote" 2>/dev/null >/dev/null; then
                echo "Script available online on GitHub "
                md5_local=`md5sum "$this_script" | cut -f1 -d" " 2>/dev/null`
                md5_remote=`curl -s "$script_remote" | md5sum | cut -f1 -d" "`
                echo "MD5 local  : "$md5_local
                echo "MD5 remote : "$md5_remote
                if [[ "$md5_local" != "$md5_remote" ]]; then
                  echo "A new version of the script is available... downloading"
                  curl -s -m 3 --create-dir -o "$this_script" "$script_remote"
                  echo "Update completed... exit"
                else
                  echo "The script is up to date... exit"
                fi
              else
                echo ""
                echo "Script offline"
              fi
            else
              echo ""
              echo "Nothing was done"
            fi
            exit 0
            ;;
    c | cron-log )
            echo -e "\033[1m$script_name_cap - latest cron log\033[0m"
            echo ""
            if [[ -f "$script_cron_log" ]]; then
              date_log=`date -r "$script_cron_log" `
              cat "$script_cron_log"
              echo ""
              echo "Log created : "$date_log
            else
              echo "No log found"
            fi
            exit 0
            ;;
    m | mode )
            needs_arg
            arg_display_mode="$OPTARG"
            display_mode_supported=( "full" )
            echo -e "\033[1m$script_name_cap - display mode override\033[0m"
            echo ""
            if [[ "${display_mode_supported[@]}" =~ "$arg_display_mode" ]]; then
              echo "Display mode activated: $arg_display_mode"
            else
              echo "Display mode $arg_display_mode not supported yet"
              exit 0
            fi
            ;;
    l | language )
            needs_arg
            display_language="$OPTARG"
            language_supported=( "fr" "en" )
            echo
            if [[ "${language_supported[@]}" =~ "$display_language" ]]; then
              echo "Language selected : $display_language"
            else
              echo "Language $display_language not supported yet"
              exit 0
            fi
            ;;
    e | edit-config )
            eval next_arg=\${$OPTIND}
            if [[ "$next_arg" == "" ]]; then
              echo -e "\033[1m$script_name_cap - config editor\033[0m"
              echo ""
              echo "No editor specified, using default (nano)"
              nano "$script_conf"
              exit 0
            else
              echo -e "\033[1m$script_name_cap - config editor\033[0m"
              echo ""
              if command -v $next_arg ; then
                echo "Editing config with: $next_arg"
                $next_arg "$script_conf"
              else
                echo "There is no software called \"$next_arg\" installed"
              fi
              exit 0
            fi
            ;;
    s | status )
            echo -e "\033[1m$script_name_cap - status (cron)\033[0m"
            echo ""
            eval next_arg=\${$OPTIND}
            if [[ "$next_arg" == @(|status) ]]; then
              echo "Checking scheduler status..."
              crontab -l > $HOME/my_old_cron.txt
              cron_check=`cat $HOME/my_old_cron.txt | grep $script_name`
              if [[ "$cron_check" != "" ]]; then
                echo "- script was added in the cron"
                cron_status=`cat $HOME/my_old_cron.txt | grep $script_name | grep "^#"`
                if [[ "$cron_status" == "" ]]; then
                  echo "- script is currently enabled"
                else
                  echo "- script is currently disabled"
                fi
              else
                echo "- script wasn't added in the cron"
              fi
            elif [[ "$next_arg" == "enable" ]]; then
              echo "Enabling the script in the cron"
              crontab -l > $HOME/my_old_cron.txt
              safety_check=`cat $HOME/my_old_cron.txt | grep $script_name | grep "^#"`
              if [[ "$safety_check" != "" ]]; then
                cat $HOME/my_old_cron.txt | grep $script_name | sed  's/^#//' > $HOME/my_new_cron.txt
                crontab $HOME/my_new_cron.txt
              else
                echo "Script is already enabled"
              fi
            elif [[ "$next_arg" == "disable" ]]; then
              echo "Disabling the script in the cron"
              crontab -l > $HOME/my_old_cron.txt
              safety_check=`cat $HOME/my_old_cron.txt | grep $script_name | grep "^#"`
              if [[ "$safety_check" == "" ]]; then
                cat $HOME/my_old_cron.txt | grep $script_name | sed 's/^/#/' > $HOME/my_new_cron.txt
                crontab $HOME/my_new_cron.txt
              else
                echo "Script is already disabled"
              fi
            fi
            rm $HOME/my_old_cron.txt 2>/dev/null
            rm $HOME/my_new_cron.txt 2>/dev/null
            exit 0
            ;;
    ??* )          die "Illegal option --$OPT" ;;  # bad long option
    ? )            exit 2 ;;  # bad short option (error reported via getopts)
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
push_notification_added_default='Fichier ajouté à Transmission\n\nFilm : $filebot_name\nFichier : $enabled_name\nTorrent : $torrent_name\nCodec : $torrent_codec\nNote IMDb : $imdb_rating\nDestination : $transmission_folder\nÉtat : $transmission_state\n\nSynopsis : $movie_synopsis'
settings_variables=( sudo c411_api_key rss_movies_url transmission_login transmission_password transmission_ip transmission_port transmission_torrent_paused rename_film plex_sort_folder skip_list approved_teams codec_preference imdb_minimum filebot_films filebot_films_H265 push_token_app push_target push_ignored push_notification_added )
required_settings=( c411_api_key transmission_login transmission_password transmission_ip transmission_port plex_sort_folder filebot_films )
edit_conf=0
mkdir -p "$(dirname "$script_conf")"
touch "$script_conf"
for script_variable in "${settings_variables[@]}"; do
  if ! grep -qE "^[[:space:]]*${script_variable}[[:space:]]*=" "$script_conf"; then
    case "$script_variable" in
      push_notification_added)
        printf 'push_notification_added="%s"\n' "$push_notification_added_default" >> "$script_conf"
        ;;
      imdb_minimum)
        printf 'imdb_minimum=""\n' >> "$script_conf"
        ;;
      transmission_torrent_paused)
        printf 'transmission_torrent_paused="no"\n' >> "$script_conf"
        ;;
      rename_film)
        printf 'rename_film="no"\n' >> "$script_conf"
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
  echo "Edit your configuration."
  echo "Use $script_bin -e"
  exit 0
fi

# Read the template literally so variables inside double quotes are expanded
# only when the notification is created, not when the config is sourced.
push_notification_added_literal=""
while IFS= read -r config_line; do
  if [[ "$config_line" =~ ^[[:space:]]*push_notification_added[[:space:]]*=(.*)$ ]]; then
    push_notification_added_literal="${BASH_REMATCH[1]}"
  fi
done < "$script_conf"
push_notification_added_literal=$(
  printf '%s' "$push_notification_added_literal" |
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
)
if (( ${#push_notification_added_literal} >= 2 )); then
  first_quote="${push_notification_added_literal:0:1}"
  last_quote="${push_notification_added_literal: -1}"
  if [[ ( "$first_quote" == '"' && "$last_quote" == '"' ) || ( "$first_quote" == "'" && "$last_quote" == "'" ) ]]; then
    push_notification_added_literal="${push_notification_added_literal:1:${#push_notification_added_literal}-2}"
  fi
fi
source "$script_conf"
push_notification_added="${push_notification_added_literal:-$push_notification_added_default}"

rename_film="${rename_film,,}"
if [[ "$rename_film" != "yes" && "$rename_film" != "no" ]]; then
  echo "Invalid rename_film value: $rename_film (expected: yes or no)"
  exit 1
fi
transmission_torrent_paused="${transmission_torrent_paused,,}"
if [[ "$transmission_torrent_paused" != "yes" && "$transmission_torrent_paused" != "no" ]]; then
  echo "Invalid transmission_torrent_paused value: $transmission_torrent_paused (expected: yes or no)"
  exit 1
fi

imdb_minimum="${imdb_minimum//,/.}"
if [[ -n "$imdb_minimum" ]]; then
  if [[ ! "$imdb_minimum" =~ ^[0-9]+([.][0-9]+)?$ ]] || ! awk -v minimum="$imdb_minimum" 'BEGIN { exit !(minimum >= 0 && minimum <= 10) }'; then
    echo "Invalid imdb_minimum value: $imdb_minimum (expected: 0 to 10)"
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
      echo "Configuration imported and saved: $variable from $conky_conf"
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
    echo "Configuration imported and saved: plex_sort_folder from $plex_sort_conf"
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
  if [[ -z "${filebot_films:-}" || -z "${filebot_films_H265:-}" ]]; then
    while IFS= read -r folder; do
      folder_name_lower=${folder##*/}
      folder_name_lower=${folder_name_lower,,}
      [[ "$folder_name_lower" == *filebot* ]] || continue
      [[ "$folder_name_lower" == *films* ]] || continue
      if [[ "$folder_name_lower" == *h265* ]]; then
        filebot_films_H265="$folder"
      else
        filebot_films="$folder"
      fi
    done < <(find "$download_folder" -mindepth 1 -maxdepth 1 -type d)
    if [[ -n "${filebot_films:-}" ]]; then
      if grep -qE '^filebot_films=' "$script_conf"; then
        sed -i "s|^filebot_films=.*|filebot_films=\"$filebot_films\"|" "$script_conf"
      else
        printf 'filebot_films="%s"\n' "$filebot_films" >> "$script_conf"
      fi
      echo "Configuration imported and saved: filebot_films=$filebot_films"
    fi
    if [[ -n "${filebot_films_H265:-}" ]]; then
      if grep -qE '^filebot_films_H265=' "$script_conf"; then
        sed -i "s|^filebot_films_H265=.*|filebot_films_H265=\"$filebot_films_H265\"|" "$script_conf"
      else
        printf 'filebot_films_H265="%s"\n' "$filebot_films_H265" >> "$script_conf"
      fi
      echo "Configuration imported and saved: filebot_films_H265=$filebot_films_H265"
    fi
  fi
fi


#######################
## Validate required settings
missing_value=0
for variable in "${required_settings[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Missing configuration: $variable"
    missing_value=1
  fi
done
if (( missing_value )); then
  echo "Use $script_bin -e"
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

printf "\e[46m \u23E5\u23E5\u23E5 \e[0m \e[46m \e[1m %-61s  \e[0m \e[46m  \e[0m \e[46m \e[0m \e[36m\u2759\e[0m\n" "$script_name_cap"
printf 'Execution log: %s\n' "$execution_log"
echo ""


#######################
## UI tags
ui_tag_ok="[\e[42m \u2713 \e[0m]"
ui_tag_bad="[\e[41m \u2717 \e[0m]"
ui_tag_info="[ \u2794 \e[0m]"
ui_tag_processed="[...\e[0m]"
ui_tag_warning="[\e[43m \u2713 \e[0m]"
ui_tag_section="\e[44m[\u2263\u2263\u2263]\e[0m \e[44m \e[1m %-*s  \e[0m \e[44m  \e[0m \e[44m \e[0m \e[34m\u2759\e[0m\n"


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
    curl_args+=(--form-string "url_title=${push_url_title:-Voir sur The Movie Database}")
  fi
  if [[ -s "$push_attachment" ]]; then
    curl_args+=(--form "attachment=@$push_attachment;type=image/jpeg")
  fi

  curl "${curl_args[@]}" "https://api.pushover.net/1/messages.json" > /dev/null
}

render-push-notification() (
  local notification="$push_notification_added"

  # Keep replacement values literal, notably ampersands in titles and plots.
  shopt -u patsub_replacement 2>/dev/null || true
  notification="${notification//\\n/$'\n'}"
  notification="${notification//\$\{title\}/$title}"
  notification="${notification//\$title/$title}"
  notification="${notification//\$\{enabled_name\}/$enabled_name}"
  notification="${notification//\$enabled_name/$enabled_name}"
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
  notification="${notification//\$\{synopsis\}/$movie_synopsis}"
  notification="${notification//\$synopsis/$movie_synopsis}"
  notification="${notification//\$\{movie_synopsis\}/$movie_synopsis}"
  notification="${notification//\$movie_synopsis/$movie_synopsis}"

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
    mui_loading_spinner="Loading..."                                                        ##
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
    movie_synopsis="Synopsis indisponible."
  elif (( ${#movie_synopsis} > 600 )); then
    movie_synopsis="${movie_synopsis:0:597}..."
  fi
  [[ "$movie_imdb_rating" =~ ^[0-9]+([.][0-9]+)?$ ]] || movie_imdb_rating="Indisponible"
  [[ "$movie_imdb_id" =~ ^tt[0-9]+$ ]] || movie_imdb_id="Indisponible"
  if [[ "$movie_tmdb_id" =~ ^[0-9]+$ ]]; then
    movie_tmdb_url="https://www.themoviedb.org/movie/$movie_tmdb_id?language=fr-FR"
  else
    movie_tmdb_id="Indisponible"
  fi
  if [[ "$movie_poster_url" == https://image.tmdb.org/t/p/* ]]; then
    movie_poster_url="${movie_poster_url/\/original\//\/w500\/}"
  else
    movie_poster_url=""
  fi
}

imdb-rating-meets-minimum() {
  local rating="$1"
  local minimum="$2"
  awk -v rating="$rating" -v minimum="$minimum" 'BEGIN { exit !(rating >= minimum) }'
}

set-torrent-comment() {
  local source_file="$1"
  local destination_file="$2"
  local comment="$3"
  local first_byte=""
  local chunk=""
  local LC_ALL=C

  exec 3<"$source_file" || return 1
  if ! IFS= read -r -N 1 first_byte <&3 || [[ "$first_byte" != "d" ]]; then
    exec 3<&-
    return 1
  fi

  {
    printf 'd7:comment%d:%s' "${#comment}" "$comment"
    # Bash cannot store NUL bytes, so copy each binary segment and restore
    # its NUL delimiter instead of loading the torrent into one variable.
    while IFS= read -r -d '' chunk <&3; do
      printf '%s\0' "$chunk"
    done
    printf '%s' "$chunk"
  } > "$destination_file"
  local status=$?
  exec 3<&-
  return "$status"
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
  if (( width >= 3648 )); then
    echo "4K"
  elif (( width >= 1824 )); then
    echo "1080p"
  elif (( width >= 1216 )); then
    echo "720p"
  else
    echo "SD"
  fi
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
approved-team-from-name() {
  local name="${1,,}"
  local team team_lower team_length prefix_length previous_char

  name=${name%.mkv}
  name=${name%.mp4}
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
  done < <(printf '%s\n' "${approved_teams:-}" | tr '|,[:space:]' '\n' | sort -fu)

  return 1
}


#######################
## Dependencies
section_title="Checking dependencies"
printf "$ui_tag_section" "$(lon2 "$section_title")" "$section_title"
dependencies=( filebot awk wget xmlstarlet locate transmission-cli curl )
missing=()
for dependency in "${dependencies[@]}"; do
  if command -v "$dependency" >/dev/null 2>&1; then
    echo -e "$ui_tag_ok Dependency: $dependency"
  else
    echo -e "$ui_tag_bad Missing dependency: $dependency"
    echo -e "$ui_tag_warning Installing dependency..."
    echo $sudo | sudo -kS apt install $dependency -y 2>/dev/null
    if $dependency -help > /dev/null 2>/dev/null ; then
      echo -e "$ui_tag_ok Dependency: $dependency"
    else
      echo -e "$ui_tag_bad manual install required: $dependency"
      missing+=("$dependency")
    fi                                                                                    ##
  fi
done
if ((${#missing[@]})); then
    echo "Use sudo apt install ${missing[*]}"
    exit 1
fi
echo ""


#######################
## Get latest movies and download
section_title="Downloading movies"
printf "$ui_tag_section" $(lon2 "$section_title") "$section_title"
rss_file="$script_folder/rss.xml"
if [[ -z "${rss_movies_url:-}" ]]; then
  rss_movies_url="https://c411.org/api/torznab?apikey=${c411_api_key}&t=movie&cat=2000"
fi

rss_temp_file=$(mktemp "/var/tmp/c411-rss.XXXXXX.xml")
if ! wget -q -O "$rss_temp_file" "$rss_movies_url"; then
  rm -f "$rss_temp_file"
  echo -e "$ui_tag_bad RSS Movies file not downloaded"
  exit 1
fi
if ! xmlstarlet val -q "$rss_temp_file" 2>/dev/null ||
   [[ "$(xmlstarlet sel -t -v 'local-name(/*)' "$rss_temp_file" 2>/dev/null)" != "rss" ]]; then
  rm -f "$rss_temp_file"
  echo -e "$ui_tag_bad Invalid RSS response (C411 may be under maintenance)"
  exit 1
fi
mv -f "$rss_temp_file" "$rss_file"
echo -e "$ui_tag_ok RSS Movies file downloaded"

while IFS=$'\t' read -r title guid enclosure_url tmdb_id; do
  echo -e "$ui_tag_info Title: $title"
  echo -e "$ui_tag_info GUID: $guid"
  torrent_file="$script_folder/torrents/$guid.torrent"
  torrent_processed=0
  torrent_skipped=0
  
  ########################################
  ## Check db file
  if grep -Fxq "$guid" "$script_db_movies_log"; then
    echo -e "$ui_tag_warning Already processed"
    echo "----------------------------------------"
    continue
  fi
  
  ########################################
  ## Skip torrent from title
  title_lower=${title,,}
  skip_list_sorted=$(echo "$skip_list" | tr '|' '\n' | tr '[:upper:]' '[:lower:]' | sort -u | xargs)
  for skip in $skip_list_sorted; do
    if [[ "$title_lower" == *"$skip"* ]]; then
      echo -e "$ui_tag_bad Ignored torrent title: $skip"
      torrent_skipped=1
      break
    fi
  done
  if (( torrent_skipped )); then
    if ! grep -Fxq "$guid" "$script_db_movies_log"; then
      printf '%s\n' "$guid" >> "$script_db_movies_log"
      echo -e "$ui_tag_processed Added to database"
    fi
    echo "----------------------------------------"
    continue
  fi
  
  ########################################
  ## Téléchargement du fichier torrent
  if [[ ! -s "$torrent_file" ]]; then
    if wget -q "$enclosure_url" -O "$torrent_file"; then
      echo -e "$ui_tag_ok Torrent file downloaded"
    else
      echo -e "$ui_tag_bad Unable to download torrent file"
      rm -f "$torrent_file"
      echo "----------------------------------------"
      continue
    fi
  fi
  
  ########################################
  ## Récupération du nom interne du torrent
  torrent_name=$(transmission-show "$torrent_file" | sed -nE 's/^[[:space:]]*Name:[[:space:]]*//p' | head -n 1)
  if [[ -z "$torrent_name" ]]; then
    echo -e "$ui_tag_bad Unable to determine torrent name"
    echo "----------------------------------------"
    continue
  fi
  
  ########################################
  ## Extraction de tous les fichiers MKV
  #mapfile -t new_files < <(transmission-show "$torrent_file" | sed -n '/FILES/,$p' | grep -i '\.mkv' | sed 's/^[[:space:]]*//' | sed 's/\.mkv.*/.mkv/I')
  mapfile -t new_files < <(transmission-show "$torrent_file" | sed -n '/FILES/,$p' | grep -Ei '\.(mkv|mp4)([[:space:]]|$)' | sed 's/^[[:space:]]*//' | sed -E 's/\.(mkv|mp4).*/.\1/I')
  if ((${#new_files[@]} == 0)); then
    echo -e "$ui_tag_bad No MKV/MP4 file found"
    if ! grep -Fxq "$guid" "$script_db_movies_log"; then
      printf '%s\n' "$guid" >> "$script_db_movies_log"
      echo -e "$ui_tag_processed Added to database"
    fi
    echo "----------------------------------------"
    continue
  fi

  ########################################
  ## Filtre des teams autorisées
  if [[ -n "${approved_teams:-}" ]]; then
    approved_team=""
    for release_name in "${new_files[@]}" "$torrent_name" "$title"; do
      if approved_team=$(approved-team-from-name "$(basename "$release_name")"); then
        break
      fi
    done
    if [[ -z "$approved_team" ]]; then
      echo -e "$ui_tag_bad Release team ignored (approved: $approved_teams)"
      if ! grep -Fxq "$guid" "$script_db_movies_log"; then
        printf '%s\n' "$guid" >> "$script_db_movies_log"
        echo -e "$ui_tag_processed Added to database"
      fi
      echo "----------------------------------------"
      continue
    fi
    echo -e "$ui_tag_ok Approved release team: $approved_team"
  fi
  
  ########################################
  ## Analyse de tous les MKV
  accepted_files=()
  accepted_codecs=()
  accepted_movie_names=()
  accepted_movie_synopses=()
  accepted_imdb_ratings=()
  accepted_imdb_ids=()
  accepted_tmdb_ids=()
  accepted_tmdb_urls=()
  accepted_poster_urls=()
  for my_file_raw in "${new_files[@]}"; do
    my_file=$(basename "$my_file_raw")
    my_file_lower=${my_file,,}
    my_file_codec=$(detect-codec-from-name "$my_file_lower")
    if [[ "$my_file_codec" == "Unknown" ]]; then
      my_file_codec=$(detect-codec-from-name "$title_lower")
    fi
    echo -e "$ui_tag_ok File: $my_file"
    
    ########################################
    ## Analyse FileBot
    temp_dir=$(mktemp -d "/var/tmp/c411-filebot.XXXXXX")
    filebot_input_name="$my_file"
    if ((${#new_files[@]} == 1)) && [[ -n "${title//[[:space:]]/}" ]]; then
      filebot_input_name="${title//\// -}.${my_file##*.}"
      filebot_input_name="${filebot_input_name//\\/ -}"
    fi
    temp_file="$temp_dir/$filebot_input_name"
    touch "$temp_file"
    filebot_name_full=$(filebot --action test -script fn:amc -non-strict --conflict override --lang fr --encoding UTF-8 -rename "$temp_file" --def minFileSize=0 minLengthMS=0 --def 'seriesFormat=/SERIES/{n.replace("?", "").replace(":", "").replace("  ", " ")} - {s}x{e} - {t.replace("?", "").replace(":", "").replace("  ", " ")}' --def 'movieFormat=/MOVIE/{n.replace("?", "").replace(":", "").replace("  ", " ")} ({y})' --output "$temp_dir" 2>/dev/null | grep '\[TEST\]' | sed -n 's/^.* to \[\(.*\)\]$/\1/p' | head -n 1)

    filebot_retry_reason=""
    if [[ -z "$filebot_name_full" ]]; then
      filebot_retry_reason="name not found"
    elif [[ "$filebot_name_full" == */SERIES/* ]]; then
      filebot_retry_reason="incorrect TV series detection"
    fi

    if [[ "$tmdb_id" =~ ^[0-9]+$ ]]; then
      if ((${#new_files[@]} == 1)); then
        echo -e "$ui_tag_info Identifying movie with RSS TMDb ID: $tmdb_id"
        forced_filebot_name_full=$(filebot -rename "$temp_file" --q "$tmdb_id" --db TheMovieDB --lang fr --encoding UTF-8 --action test --format '/MOVIE/{n.replace("?", "").replace(":", "").replace("  ", " ")} ({y})' --output "$temp_dir" 2>/dev/null | sed -n 's/^.* to \[\(.*\)\]$/\1/p' | head -n 1)
        if [[ "$forced_filebot_name_full" == */MOVIE/* ]]; then
          filebot_name_full="$forced_filebot_name_full"
          echo -e "$ui_tag_ok FileBot name found with TMDb ID: $(basename "$filebot_name_full")"
        else
          filebot_name_full=""
          echo -e "$ui_tag_bad FileBot TMDb movie identification failed: $tmdb_id"
        fi
      elif [[ -n "$filebot_retry_reason" ]]; then
        echo -e "$ui_tag_warning TMDb ID fallback skipped: torrent contains multiple video files"
      fi
    fi
    rm -rf "$temp_dir"

    if [[ -z "$filebot_name_full" ]]; then
      torrent_skipped=1
      echo -e "$ui_tag_bad FileBot issue: no name found"
      continue
    fi
    
    ########################################
    ## Series detection
    if [[ "$filebot_name_full" == */SERIES/* ]]; then
      echo -e "$ui_tag_bad TV Series detected: $my_file"
      torrent_skipped=1
      continue
    fi
    if [[ "$filebot_name_full" != */MOVIE/* ]]; then
      echo -e "$ui_tag_bad Unknown FileBot media type"
      continue
    fi
    filebot_name=$(basename "$filebot_name_full")
    echo -e "$ui_tag_ok FileBot name: $filebot_name"
    
    ########################################
    ## Filtres
    if [[ "$my_file_lower" != *"1080p"* && "$title_lower" != *"1080p"* ]]; then
      echo -e "$ui_tag_bad Resolution ignored: 1080p required"
      torrent_skipped=1
      continue
    fi
    skip_list_sorted=$(echo "$skip_list" | tr '|' '\n' | tr '[:upper:]' '[:lower:]' | sort -u | xargs)
    for skip in $skip_list_sorted; do
      if [[ "$my_file_lower" == *"$skip"* ]]; then
        echo -e "$ui_tag_bad Ignored release: $skip"
        torrent_skipped=1
        continue 2
      fi
    done

    ########################################
    ## FileBot metadata and optional IMDb rating filter
    movie_name="${filebot_name%.*}"
    get-movie-metadata "$movie_name" "$tmdb_id"
    echo -e "$ui_tag_info IMDb rating: $movie_imdb_rating"
    if [[ -n "$imdb_minimum" ]]; then
      if [[ ! "$movie_imdb_rating" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        echo -e "$ui_tag_bad IMDb rating unavailable (minimum required: $imdb_minimum)"
        torrent_skipped=1
        continue
      elif ! imdb-rating-meets-minimum "$movie_imdb_rating" "$imdb_minimum"; then
        echo -e "$ui_tag_bad IMDb rating ignored: $movie_imdb_rating < $imdb_minimum"
        torrent_skipped=1
        continue
      else
        echo -e "$ui_tag_ok IMDb rating accepted: $movie_imdb_rating >= $imdb_minimum"
      fi
    fi
    
    ########################################
    ## Checking for the presence of a local file
    if [[ -n "${plex_sort_folder:-}" ]]; then
      mapfile -t locate_databases < <(find "$plex_sort_folder" -maxdepth 1 -type f -name "*.locate.db" | sort)
      local_check=""
      for locate_db in "${locate_databases[@]}"; do
        local_check+=$'\n'"$(locate -i -d "$locate_db" -- "$filebot_name" || true)"
      done
      local_check=$(printf '%s\n' "$local_check" | sed '/^$/d')
    else
      local_check=$(locate -i -- "$filebot_name" | grep -viE '/mnt/Plex/|/\.Trash/' || true)
    fi
    if [[ -n "$local_check" ]]; then
      local_check_file=$(printf '%s\n' "$local_check" | head -n 1)
      local_check_width=$(mediainfo --Inform="Video;%Width%" "$local_check_file")
      local_check_height=$(mediainfo --Inform="Video;%Height%" "$local_check_file")
      local_check_standard_resolution=$(resolution-standard "$local_check_width" "$local_check_height")
      local_check_codec_raw=$(mediainfo --Inform="Video;%Format%" "$local_check_file")
      local_check_codec=$(codec-standard "$local_check_codec_raw")
      echo -e "$ui_tag_processed Movie found: $local_check_file"
      echo -e "$ui_tag_processed Movie resolution: $local_check_standard_resolution"
      echo -e "$ui_tag_processed Movie codec: $local_check_codec"

      if [[ "$local_check_standard_resolution" == "720p" || "$local_check_standard_resolution" == "SD" ]]; then
        echo -e "$ui_tag_ok Resolution upgrade: $local_check_standard_resolution -> 1080p"
      elif [[ "$my_file_codec" == "$local_check_codec" ]]; then
        echo -e "$ui_tag_processed Local version already uses the same codec: $local_check_codec"
        torrent_skipped=1
        continue
      elif [[ -n "${codec_preference:-}" && "$my_file_codec" == "$codec_preference" ]]; then
        echo -e "$ui_tag_ok Codec replacement: $local_check_codec -> $my_file_codec (preferred: $codec_preference)"
      elif [[ -n "${codec_preference:-}" ]]; then
        echo -e "$ui_tag_processed Codec ignored: $my_file_codec (preferred: $codec_preference)"
        torrent_skipped=1
        continue
      else
        echo -e "$ui_tag_ok Codec replacement: $local_check_codec -> $my_file_codec"
      fi
    else
      echo -e "$ui_tag_ok No local movie found: codec preference not applied ($my_file_codec)"
    fi
    echo -e "$ui_tag_ok New movie detected"
    
    accepted_files+=("$my_file_raw")
    accepted_codecs+=("$my_file_codec")
    accepted_movie_names+=("$movie_name")
    accepted_movie_synopses+=("$movie_synopsis")
    accepted_imdb_ratings+=("$movie_imdb_rating")
    accepted_imdb_ids+=("$movie_imdb_id")
    accepted_tmdb_ids+=("$movie_tmdb_id")
    accepted_tmdb_urls+=("$movie_tmdb_url")
    accepted_poster_urls+=("$movie_poster_url")
  done
  
  ########################################
  ## Aucun fichier accepté
  if ((${#accepted_files[@]} == 0)); then
    echo -e "$ui_tag_bad No accepted MKV/MP4 file"
    if (( torrent_skipped )); then
      if ! grep -Fxq "$guid" "$script_db_movies_log"; then
        printf '%s\n' "$guid" >> "$script_db_movies_log"
        echo -e "$ui_tag_processed Added to database"
      fi
    fi
    echo "----------------------------------------"
    continue
  fi
  #echo -e "$ui_tag_ok Accepted files: ${#accepted_files[@]}"
  transmission_host="$transmission_ip:$transmission_port"
  transmission_auth="$transmission_login:$transmission_password"
  
  ########################################
  ## Recherche d’un torrent déjà présent
  torrent_id=$(transmission-remote "$transmission_host" -n "$transmission_auth" -l | grep -F -- "$torrent_name" | head -n 1 | awk '{print $1}')
  if [[ -n "$torrent_id" ]]; then
    echo -e "$ui_tag_warning Torrent already present in Transmission (ID: $torrent_id)"
    # Aucun fichier n’est désactivé ou réactivé sur un torrent existant.
    torrent_processed=1
  else
    ########################################
    ## Destination
    torrent_codec="Unknown"
    for accepted_codec in "${accepted_codecs[@]}"; do
      if [[ "$accepted_codec" == "H265" ]]; then
        torrent_codec="H265"
        break
      elif [[ "$torrent_codec" == "Unknown" ]]; then
        torrent_codec="$accepted_codec"
      fi
    done

    if [[ "$torrent_codec" == "H265" && -n "${filebot_films_H265:-}" && -d "$filebot_films_H265" ]]; then
      transmission_folder="$filebot_films_H265"
    elif [[ "$torrent_codec" == "AV1" && -n "${filebot_films_AV1:-}" && -d "$filebot_films_AV1" ]]; then
      transmission_folder="$filebot_films_AV1"
    else
      transmission_folder="$filebot_films"
    fi
    echo -e "$ui_tag_info Torrent codec: $torrent_codec"
    echo -e "$ui_tag_info Destination: $transmission_folder"
    
    ########################################
    ## Ajout en pause
    torrent_add_file="$torrent_file"
    commented_torrent_file=""
    if [[ "$rename_film" == "yes" ]]; then
      commented_torrent_file=$(mktemp "/var/tmp/c411-commented.XXXXXX.torrent")
      if set-torrent-comment "$torrent_file" "$commented_torrent_file" "$title"; then
        torrent_add_file="$commented_torrent_file"
        echo -e "$ui_tag_ok Torrent comment added: $title"
      else
        echo -e "$ui_tag_warning Unable to add torrent comment"
        rm -f "$commented_torrent_file"
        commented_torrent_file=""
      fi
    fi
    if ! transmission-remote "$transmission_host" -n "$transmission_auth" -a "$torrent_add_file" -w "$transmission_folder" -S >/dev/null 2>&1; then
      [[ -n "$commented_torrent_file" ]] && rm -f "$commented_torrent_file"
      echo -e "$ui_tag_bad Unable to add torrent"
      echo "----------------------------------------"
      continue
    fi
    [[ -n "$commented_torrent_file" ]] && rm -f "$commented_torrent_file"
    echo -e "$ui_tag_ok Torrent added paused"
    sleep 1
    
    ########################################
    ## Récupération de l’ID numérique
    torrent_id=$(transmission-remote "$transmission_host" -n "$transmission_auth" -l | grep -F -- "$torrent_name" | head -n 1 | awk '{print $1}')
    if [[ -z "$torrent_id" ]]; then
      echo -e "$ui_tag_bad Unable to retrieve torrent ID"
      echo "----------------------------------------"
      continue
    fi
    #echo -e "$ui_tag_ok Torrent ID: $torrent_id"
    
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
    enabled_poster_urls=()
    for accepted_index in "${!accepted_files[@]}"; do
      accepted_file="${accepted_files[$accepted_index]}"
      accepted_name=$(basename "$accepted_file")
      file_id=$(printf '%s\n' "$transmission_files" | grep -iF -- "$accepted_file" | head -n 1 | cut -d: -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      # Si le chemin complet ne correspond pas, essaie avec
      # seulement le nom du fichier.
      if [[ -z "$file_id" ]]; then
        file_id=$(printf '%s\n' "$transmission_files" | grep -iF -- "$accepted_name" | head -n 1 | cut -d: -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      fi
      if [[ -n "$file_id" ]]; then
#        echo -e "$ui_tag_ok File index $file_id: $accepted_name"
        enabled_file="$accepted_file"
        if [[ "$rename_film" == "yes" ]]; then
          renamed_name="${accepted_movie_names[$accepted_index]}.${accepted_name##*.}"
          if [[ "$accepted_name" != "$renamed_name" ]]; then
            if transmission-remote "$transmission_host" -n "$transmission_auth" -t "$torrent_id" --path "$accepted_file" --rename "$renamed_name" >/dev/null 2>&1; then
              if [[ "$accepted_file" == */* ]]; then
                enabled_file="${accepted_file%/*}/$renamed_name"
              else
                enabled_file="$renamed_name"
              fi
              echo -e "$ui_tag_ok Transmission file renamed: $renamed_name"
            else
              echo -e "$ui_tag_warning Unable to rename Transmission file: $accepted_name"
            fi
          fi
        fi
        accepted_file_ids+=("$file_id")
        enabled_files+=("$enabled_file")
        enabled_movie_names+=("${accepted_movie_names[$accepted_index]}")
        enabled_movie_synopses+=("${accepted_movie_synopses[$accepted_index]}")
        enabled_imdb_ratings+=("${accepted_imdb_ratings[$accepted_index]}")
        enabled_imdb_ids+=("${accepted_imdb_ids[$accepted_index]}")
        enabled_tmdb_ids+=("${accepted_tmdb_ids[$accepted_index]}")
        enabled_tmdb_urls+=("${accepted_tmdb_urls[$accepted_index]}")
        enabled_poster_urls+=("${accepted_poster_urls[$accepted_index]}")
#      else
#        echo -e "$ui_tag_bad File index not found: $accepted_name"
      fi
    done
    
    ########################################
    ## No accepted file index found : Transmission file deleted 
    if ((${#accepted_file_ids[@]} == 0)); then
      echo -e "$ui_tag_bad No accepted file index found"
      transmission-remote "$transmission_host" -n "$transmission_auth" -t "$torrent_id" -r >/dev/null 2>&1
      echo "----------------------------------------"
      continue
    fi
    
    ########################################
    ## Listing of selected files 
    file_ids=$(IFS=,; echo "${accepted_file_ids[*]}")
    echo -e "$ui_tag_info Enabled file indexes: $file_ids"
    
    ########################################
    ## Disable all files
    if ! transmission-remote "$transmission_host" -n "$transmission_auth" -t "$torrent_id" -G all >/dev/null 2>&1; then
      echo -e "$ui_tag_bad Unable to disable torrent files"
      echo "----------------------------------------"
      continue
    fi
    
    ########################################
    ## Only enable selected files
    if ! transmission-remote "$transmission_host" -n "$transmission_auth" -t "$torrent_id" -g "$file_ids" >/dev/null 2>&1; then
      echo -e "$ui_tag_bad Unable to enable selected files"
      echo "----------------------------------------"
      continue
    fi
    
    ########################################
    ## Starting torrent
    if [[ "$transmission_torrent_paused" == "yes" ]]; then
      echo -e "$ui_tag_warning Download in pause"
      transmission_state="En pause"
      torrent_processed=1
    else
     if transmission-remote "$transmission_host" -n "$transmission_auth" -t "$torrent_id" -s >/dev/null 2>&1; then
        echo -e "$ui_tag_ok Download started"
        for enabled_file in "${enabled_files[@]}"; do
          echo -e "$ui_tag_ok Enabled: $(basename "$enabled_file")"
        done
        transmission_state="Téléchargement démarré"
        torrent_processed=1
      else
        echo -e "$ui_tag_bad Unable to start torrent"
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
        movie_poster_url="${enabled_poster_urls[$enabled_index]}"
        push_content=$(render-push-notification)
        poster_file=""
        if [[ -n "$movie_poster_url" ]]; then
          poster_file=$(mktemp "/var/tmp/c411-poster.XXXXXX")
          if ! curl --silent --show-error --fail --location --max-time 20 --output "$poster_file" "$movie_poster_url"; then
            echo -e "$ui_tag_warning Unable to download movie poster: $movie_name"
            rm -f "$poster_file"
            poster_file=""
          elif (( $(stat -c %s "$poster_file") > 5242880 )); then
            echo -e "$ui_tag_warning Movie poster exceeds Pushover limit: $movie_name"
            rm -f "$poster_file"
            poster_file=""
          fi
        fi
        if push-message "Fichier ajouté à Transmission" "$push_content" "-1" "$movie_tmdb_url" "Voir sur The Movie Database" "$poster_file"; then
          echo -e "$ui_tag_ok Push sent: $enabled_name"
        else
          echo -e "$ui_tag_bad Unable to send push: $enabled_name"
        fi
        [[ -n "$poster_file" ]] && rm -f "$poster_file"
      done
    fi
  fi
  
  ########################################
  ## Add GUID to db file
  if (( torrent_processed )); then
    if ! grep -Fxq "$guid" "$script_db_movies_log"; then
      printf '%s\n' "$guid" >> "$script_db_movies_log"
    fi
  fi
  echo "----------------------------------------"
done < <(
  xmlstarlet sel \
    -N 'torznab=http://torznab.com/schemas/2015/feed' \
    -T \
    -t \
    -m '/rss/channel/item' \
    -v 'normalize-space(title)' \
    -o $'\t' \
    -v 'normalize-space(guid)' \
    -o $'\t' \
    -v 'enclosure/@url' \
    -o $'\t' \
    -v 'torznab:attr[@name="tmdbid"]/@value' \
    -n \
    "$rss_file"
)
