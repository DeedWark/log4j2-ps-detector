# log4j2-ps-detector

# Info
```
1 - Check if Java process is running
2 - Get Java class for each running process
3 - Get log4j version
4 - Check if log4j2.formatMsgNoLookups=true on Java command
5 - Check if there is '%m, %msg, %message' or '$${ctx:' in Java configuration file
6 - Use log4j-detector (Java) to detect the danger level of each log4j elements
7 - Export everything to a CSV file in this format: 
    hostname; java_process; java_class; log4j_version; formatNoLookups=true; %pattern; ctx; log4j-detector verdict;
```

# Usage [Debian based, Ubuntu...]
```bash
bash log4j2-ps-detector.sh
```
