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
script_name=$(basename $0 | cut -d'.' -f1)
script_name_cap=${script_name^^}
script_name_full=$(basename $0)
script_bin=$0
script_conf=`echo $HOME"/.config/"$script_name"/"$script_name".conf"`
script_remote="https://raw.githubusercontent.com/Z0uZOU/$script_name/main/$script_name_full"
script_cron_log=`echo "/var/log/"$script_name".log"`
script_folder="$HOME/.config/$script_name"
script_db_movies_log="$HOME/.config/$script_name/db_movies.log"
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
## Script configuration
settings_variables=( sudo c411_api_key rss_movies_url transmission_login transmission_password transmission_ip transmission_port transmission_torrent_paused plex_sort_folder skip_list codec_preference filebot_films filebot_films_H265 push_token_app push_target push_ignored )
required_settings=( c411_api_key transmission_login transmission_password transmission_ip transmission_port plex_sort_folder filebot_films )
edit_conf=0
mkdir -p "$(dirname "$script_conf")"
touch "$script_conf"
for script_variable in "${settings_variables[@]}"; do
  if ! grep -qE "^[[:space:]]*${script_variable}[[:space:]]*=" "$script_conf"; then
    printf '%s=""\n' "$script_variable" >> "$script_conf"
    edit_conf=1
  fi
done
if (( edit_conf )); then
  echo "Edit your configuration."
  echo "Use $script_bin -e"
  exit 0
fi
source "$script_conf"

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
if [[ -r "$plex_sort_folder/plex_sort.conf" ]]; then
  download_folder=$(sed -nE 's|^[[:space:]]*download_folder[[:space:]]*=[[:space:]]*"([^"]*)".*$|\1|p' "$plex_sort_folder/plex_sort.conf" | head -n1)
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

printf "\e[46m\u23E5\u23E5   \e[0m \e[46m \e[1m %-61s  \e[0m \e[46m  \e[0m \e[46m \e[0m \e[36m\u2759\e[0m\n" "$script_name_cap"
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
  push_title=$1
  push_content=$2
  push_priority=$3
  if [[ "$push_priority" == "" ]]; then
    push_priority="-1"
  fi
  for user in {1..10}; do
    target=`eval echo "\\$target_"$user`
    if [ -n "$target" ]; then
      curl -s \
        --form-string "token=$token_app" \
        --form-string "user=$target" \
        --form-string "title=$push_title" \
        --form-string "message=$push_content" \
        --form-string "html=1" \
        --form-string "priority=$push_priority" \
        https://api.pushover.net/1/messages.json > /dev/null
    fi
  done
}


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


#######################
## Dependencies
section_title="Checking dependencies"
printf "$ui_tag_section" "$(lon2 "$section_title")" "$section_title"
dependencies=( filebot awk wget xmlstarlet locate transmission-cli )
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

if wget -q -O "$rss_file" "$rss_movies_url"; then
    echo -e "$ui_tag_ok RSS Movies file downloaded"
else
    echo -e "$ui_tag_bad RSS Movies file not downloaded"
    exit 1
fi

while IFS=$'\t' read -r title guid enclosure_url; do
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
  ## Analyse de tous les MKV
  accepted_files=()
  accepted_codecs=()
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
    temp_file="$temp_dir/$my_file"
    touch "$temp_file"
    filebot_name_full=$(filebot --action test -script fn:amc -non-strict --conflict override --lang fr --encoding UTF-8 -rename "$temp_file" --def minFileSize=0 minLengthMS=0 --def 'seriesFormat=/SERIES/{n.replace("?", "").replace(":", "").replace("  ", " ")} - {s}x{e} - {t.replace("?", "").replace(":", "").replace("  ", " ")}' --def 'movieFormat=/MOVIE/{n.replace("?", "").replace(":", "").replace("  ", " ")} ({y})' --output "$temp_dir" 2>/dev/null | grep '\[TEST\]' | sed -n 's/^.* to \[\(.*\)\]$/\1/p' | head -n 1)
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
    if ! transmission-remote "$transmission_host" -n "$transmission_auth" -a "$torrent_file" -w "$transmission_folder" -S >/dev/null 2>&1; then
      echo -e "$ui_tag_bad Unable to add torrent"
      echo "----------------------------------------"
      continue
    fi
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
    for accepted_file in "${accepted_files[@]}"; do
      accepted_name=$(basename "$accepted_file")
      file_id=$(printf '%s\n' "$transmission_files" | grep -iF -- "$accepted_file" | head -n 1 | cut -d: -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      # Si le chemin complet ne correspond pas, essaie avec
      # seulement le nom du fichier.
      if [[ -z "$file_id" ]]; then
        file_id=$(printf '%s\n' "$transmission_files" | grep -iF -- "$accepted_name" | head -n 1 | cut -d: -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      fi
      if [[ -n "$file_id" ]]; then
#        echo -e "$ui_tag_ok File index $file_id: $accepted_name"
        accepted_file_ids+=("$file_id")
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
      torrent_processed=1
    else
     if transmission-remote "$transmission_host" -n "$transmission_auth" -t "$torrent_id" -s >/dev/null 2>&1; then
        echo -e "$ui_tag_ok Download started"
        for accepted_file in "${accepted_files[@]}"; do
          echo -e "$ui_tag_ok Enabled: $(basename "$accepted_file")"
        done
        torrent_processed=1
      else
        echo -e "$ui_tag_bad Unable to start torrent"
      fi
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
    -T \
    -t \
    -m '/rss/channel/item' \
    -v 'normalize-space(title)' \
    -o $'\t' \
    -v 'normalize-space(guid)' \
    -o $'\t' \
    -v 'enclosure/@url' \
    -n \
    "$rss_file"
)
