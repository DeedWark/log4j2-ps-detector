#!/bin/bash
# Description: Check log4j failure in java process
# Author: Me
# Date: 2022-01-06
# Version: 1.0

# STEPS:
# 1 - Check if Java process is running
# 2 - Get Java class for each running process
# 3 - Get log4j version
# 4 - Check if log4j2.formatMsgNoLookups=true on Java command
# 5 - Check if there is '%m, %msg, %message' or '$${ctx:' in Java configuration file
# 6 - Use log4j-detector (Java) to detect the danger level of each log4j elements
# 7 - Export everything to a CSV file in this format: 
#     hostname; java_process; java_class; log4j_version; formatNoLookups=true; %pattern; ctx; log4j-detector verdict;

##############################
##        VARIABLE          ##
##############################
_SERVER=$(hostname)
_JAVA_PROCESS_LIST=$(pgrep -i java)
_CSV_EXPORT_FILE="/tmp/csv_export_file.csv"
_LOG4J_DETECTOR="/tmp/log4j-detector-latest.jar"
#########   ARRAY  ###########
_ARRAY_CSV=()
############ END #############

##############################
##        FUNCTION          ##
##############################
# Check if unzip is installed
check_unzip() {
  _UNZIP_INSTALLED=0
  if ! which unzip &>/dev/null; then
    echo "UNZIP not found on this server, please wait..."
    apt-get install unzip -y
    _UNZIP_INSTALLED=1
  fi
}

# Check if log4j-detector is present else download it
check_log4j_detector() {
  _LOG4J_DETECTOR_INSTALLED=0
  if [ ! -f "$_LOG4J_DETECTOR" ]; then
    echo -e "Download log4j-detector from github\n"
    wget -q https://github.com/mergebase/log4j-detector/raw/master/log4j-detector-latest.jar -O "$_LOG4J_DETECTOR" || curl -s https://github.com/mergebase/log4j-detector/raw/master/log4j-detector-latest.jar -o "$_LOG4J_DETECTOR"
    _LOG4J_DETECTOR_INSTALLED=1
  fi

  # Last check if wget / curl didn't work
  [[ ! -f "$_LOG4J_DETECTOR" ]] && echo "$_LOG4J_DETECTOR not found, exiting" && exit 1
}
############ END ##############

###############################
##          MAIN             ##
###############################
# Empty CSV and init it
: > "$_CSV_EXPORT_FILE"
echo -e "SERVERNAME; JAVA PROCESS; JAVA CLASS; LOG4J VERSION; log4j2.formatMsgNoLookups=true; %m, %msg, %message; ctx; log4j-detector verdict" > "$_CSV_EXPORT_FILE"

# Check if there is java process
[[ -z "$_JAVA_PROCESS_LIST" ]] && echo "No running JAVA process found on this server!" && echo -e "$_SERVER; NO JAVA PROCESS FOUND ON THIS SERVER;" >> "$_CSV_EXPORT_FILE"  && exit 0

# Check packages
check_unzip
check_log4j_detector

for _process in $_JAVA_PROCESS_LIST; do

  # RESET _ARRAY_CSV to do
  _ARRAY_CSV=()

  # Add hostname to CSV
  _ARRAY_CSV+=("$_SERVER;")

  # Get whole JAVA command
  _JAVA_CMD=$(ps -p "$_process" -o command --no-headers)
  
  # Add _JAVA_CMD (java command) to CSV
  _ARRAY_CSV+=("$_JAVA_CMD;")

  # Get JAVA class only
  _JAVA_CLASS=$(echo "$_JAVA_CMD" | grep -ioE '\s[a-z]{2,3}\..+(\s|$)' | tr -d ' ')

  # Add _JAVA_CLASS (com.domain.product.service.Service) to CSV
  _ARRAY_CSV+=("$_JAVA_CLASS;")

  # Get LOG4J version
  # Get only java file in java command
  _JAVA_FILE=$(echo "$_JAVA_CMD" | grep -Eo -- '-cp [^ ]+' | sed -E 's/-cp //' | sed -E 's/\:/\ /g')

  # For each file in $_JAVA_FILE
  for _file in $_JAVA_FILE; do

    # If _file ends with .jar
    if [[ $_file =~ .+\.[jJ][aA][rR](\s|$) ]]; then
    
      for _element in $(unzip -l "$_file" | grep "log4j" | grep "META-INF" | grep "pom.xml" | awk '{print $4}'); do

        # Get log4j version (1.2.3)
        _LOG4J_VERSION=$(unzip -p "$_file" "$_element" | \
                         grep -A 2 -m 1 "groupId>org.apache.logging.log4j" | \
                         grep -ioE 'version>(.+)<' | \
                         awk -F '>|<' '{print $2}' | \
                         grep -E '^[0-9].+')
        
        # Add all log4j version results to an array in order to select the first index later
        [[ -n "$_LOG4J_VERSION" ]] && _LOG4J_ONLY_VERSION=() && _LOG4J_ONLY_VERSION+=("$_LOG4J_VERSION")

      done #_element

    fi #_file .jar

  done # _file

  # Add first index of log4j version to CSV file 
  [[ -n "${_LOG4J_ONLY_VERSION[*]}" ]] && _ARRAY_CSV+=("${_LOG4J_ONLY_VERSION[0]};") || _ARRAY_CSV+=("N/A;")

  # Check if log4j2.formatMsgNoLookups is present in java command
  [[ ! "$_JAVA_CMD" =~ log4j2.formatMsgNoLookups=true ]] && _ARRAY_CSV+=("false;") || _ARRAY_CSV+=("true;")
 
  echo "${_ARRAY_CSV[@]}" >> "$_CSV_EXPORT_FILE"

done # FINAL DONE

[[ $_UNZIP_INSTALLED -eq 1 ]] && apt remove --purge unzip -y


# Check if %m, %msg, %message is present in log4j configuration file
_JAVA_CONF_FILE=$(ps fauwwx | grep -i java | grep -Eo -- '-cp [^ ]+' | sed -E 's/-cp //' | sed -E 's/\:/\ /g')
for _file in $_JAVA_CONF_FILE; do
  # match %m, %msg, %message in conf file and get conf file path only
  _PATTERN_MATCHED=$(rgrep '%m\|%msg\|%message' "$_file" 2>/dev/null | grep -vi binary | grep -i 'log4j2' | awk -F ':' '{print $1}' | sort -u)

  if [[ -n "$_PATTERN_MATCHED" ]]; then
    for _value_pm in $_PATTERN_MATCHED; do
      echo "$_SERVER;;;;; $_value_pm;;" >> "$_CSV_EXPORT_FILE" 
    done
  fi
done

# Check if '$${ctx:' is present in configuration file
for _file in $_JAVA_CONF_FILE; do
  # match $${ctx: in conf file and get conf file path only
  _CTX_MATCHED=$(rgrep '$${ctx:' "$_file" 2>/dev/null | grep -vi binary | grep -i 'log4j2' | awk -F ':' '{print $1}' | sort -u)

  if [[ -n "$_CTX_MATCHED" ]]; then
    for _value_cm in $_CTX_MATCHED; do
      echo "$_SERVER;;;;;; $_value_cm;" >> "$_CSV_EXPORT_FILE"
    done
  fi

done

# Log4j-detector path
for _file in $_JAVA_CONF_FILE; do
  # Check with log4j-detector
  _RUN_JAR=$(java -jar "$_LOG4J_DETECTOR" "$_file" 2>&1 | grep -iE '_.+_' | grep -vi 'okay')

  if [[ -n "$_RUN_JAR" ]]; then
    while read -r _value_rj; do
      if [[ -n "$_value_rj" ]]; then
        echo "$_SERVER;;;;;;; $_RUN_JAR;" >> "$_CSV_EXPORT_FILE"
      fi
    done <<< "$_RUN_JAR"
  fi

done

[[ $_LOG4J_DETECTOR_INSTALLED -eq 1 ]] && rm "$_LOG4J_DETECTOR" && exit 0
############ END ##############
