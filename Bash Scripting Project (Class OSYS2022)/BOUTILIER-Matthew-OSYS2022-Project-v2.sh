##########################################
### Title: Port Scan Monitor Script    ###
### Author: Matthew Boutilier          ###
### Student ID: W0498901               ###
### Course: OSYS2022 - Linux Scripting ###
### Created: 2025-03-20                ###
### Last Modified: 2025-04-06          ###
##########################################

#!/bin/bash

# =========[ Configuration Variables ]=========

# Define the directory where scan logs will be saved
SCAN_DIR="$HOME/scan_logs"

# Define the files used to compare current and previous scan results
PREV_SCAN="$SCAN_DIR/prev_scan.txt"
CURR_SCAN="$SCAN_DIR/cur_scan.txt"

# Define a tag used to identify cron jobs created by this script
CRON_TAG="#NET_SCAN_JOB"

# Define the location of the userâ€™s configuration file
CONFIG_FILE="$HOME/.portscanrc"

# Define the sender email address used by msmtp
SENDER="w0498901.script@gmail.com"

# Define the default range of ports to scan
DEFAULT_PORT_RANGE="1-1024"

# =========[ Setup Directories and Configs ]=========

# Ensure the scan log directory exists
mkdir -p "$SCAN_DIR"

# Load port range from config file if it exists; otherwise, create the config with the default
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "PORT_RANGE=$DEFAULT_PORT_RANGE" > "$CONFIG_FILE"
    source "$CONFIG_FILE"
fi

# =========[ Input Validators ]=========

# Validate that the provided string is a properly formatted IPv4 address
validate_ip() {
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] &&
    for i in ${1//./ }; do ((i >= 0 && i <= 255)) || return 1; done
}

# Validate that the provided string is a properly formatted email address
validate_email() {
    [[ "$1" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

# =========[ Email Sending Function ]=========

# Send an email using msmtp with the specified recipient, IP, and message body
send_msmtp() {
    local recipient="$1"
    local ip="$2"
    local body="$3"

    # Format and send the message using msmtp
    echo -e "From: \"Port Scan Alert\" <$SENDER>\nSubject: Automated Network Security Alert\n\nALERT\n$body" | \
    msmtp --from="$SENDER" "$recipient"
}

# =========[ One-Time Port Scan ]=========

# Perform a single scan and optionally email the results
one_time_scan() {
    read -p "Enter IP address: " ip

    # Validate the entered IP
    validate_ip "$ip" || { echo "Invalid IP format."; return; }

    # Define the name of the scan output file based on current date/time
    output_file="$SCAN_DIR/scan_$(date +%Y%m%d_%H%M%S).txt"

    # Scan the target IP and store results of successful ports
    nc -zv -w1 "$ip" $PORT_RANGE 2>&1 | grep -i "succeeded" > "$output_file"

    echo ""
    echo "Would you like to email the results? (y/n)"
    read -p "Choice: " email_opt

    # If email option selected, prompt for and validate email address
    if [[ "$email_opt" == "y" || "$email_opt" == "Y" ]]; then
        read -p "Enter your email: " email
        validate_email "$email" || { echo "Invalid email format."; return; }

        # Format the body of the email with scan results
        body="Port scan completed on $ip.\n\nResults:\n$(cat "$output_file")"

        # Send the email
        send_msmtp "$email" "$ip" "$body"
    else
        echo "Results saved locally: $output_file"
    fi

    # Notify the user that the scan is complete
    notify-send -u critical "Port Scan Monitor" "Scan complete for $ip"
}

# =========[ Recurring Scan Job Setup ]=========

# Schedule a recurring scan using cron
recurring_scan() {
    read -p "Enter IP address: " ip
    validate_ip "$ip" || { echo "Invalid IP format."; return; }

    read -p "Scan interval in hours (3â€“168): " hours
    ((hours >= 3 && hours <= 168)) || { echo "Invalid interval."; return; }

    read -p "Enter your email: " email
    validate_email "$email" || { echo "Invalid email format."; return; }

    # Define the path for the scan job script
    scan_script="$SCAN_DIR/scan_job.sh"

    # Write a reusable scan script to disk for use in cron
    cat <<EOF > "$scan_script"
#!/bin/bash
ip="$ip"
recipient="$email"
output="$CURR_SCAN"
prev="$PREV_SCAN"
SENDER="$SENDER"
PORT_RANGE="$PORT_RANGE"
body="Automated script detected changes in port status on \$ip. Please verify network security."

nc -zv -w1 \$ip \$PORT_RANGE 2>&1 | grep -i "succeeded" > "\$output"
if [ -f "\$prev" ]; then
    diff_out=\$(diff "\$prev" "\$output")
    if [ ! -z "\$diff_out" ]; then
        echo -e "From: \"Port Scan Alert\" <\$SENDER>\nSubject: Port Change Detected\n\nALERT\n\$body\n\nDifferences:\n\$diff_out" | msmtp --from="\$SENDER" "\$recipient"
        notify-send -u critical "Port Scan Monitor" "Port change detected on \$ip"
    fi
fi
cp "\$output" "\$prev"
EOF

    # Make the script executable
    chmod +x "$scan_script"

    # Schedule the scan job in cron using the specified interval and a unique tag
    (crontab -l 2>/dev/null; echo "0 */$hours * * * $scan_script $CRON_TAG") | crontab -
    echo "Recurring scan set every $hours hours."
}

# =========[ Stop Recurring Scans ]=========

# Remove any cron jobs added by this script
stop_recurring() {
    crontab -l 2>/dev/null | grep "$CRON_TAG"
    echo "Remove all recurring scans? (y/n): "
    read answer

    # If user confirms, remove the tagged cron lines
    if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
        crontab -l 2>/dev/null | grep -v "$CRON_TAG" | crontab -
        echo "Recurring scan stopped."
    else
        echo "No changes made."
    fi
}

# =========[ Help & Configuration Menu ]=========

# Show options to the user for help, editing config, and updating settings
show_help() {
    while true; do
        echo ""
        echo "   Help Menu"
        echo "   ==================="
        echo "1. User Instructions"
        echo "2. Change Scanned Port Range (currently: $PORT_RANGE)"
        echo "3. Edit msmtp Config File"
        echo "4. Back to Main Menu"
        read -p "Choose an option: " help_opt

        case $help_opt in
            1)
                echo ""
                echo "- IP address format must follow ###.###.###.###"
                echo "- Email address format must follow example@domain.com"
                echo "- Programmer Contact: W0498901@nscc.ca"
                ;;
            2)
                read -p "Enter new port range (e.g., 1-65535): " new_range

                # Validate the format of the port range before saving
                if [[ "$new_range" =~ ^[0-9]+-[0-9]+$ ]]; then
                    echo "PORT_RANGE=$new_range" > "$CONFIG_FILE"
                    source "$CONFIG_FILE"
                    echo "Port range updated to $PORT_RANGE"
                else
                    echo "Invalid port range format."
                fi
                ;;
            3)
                # Open the msmtp config file in nano
                nano ~/.msmtprc
                ;;
            4)
                return
                ;;
            *)
                echo "Invalid choice."
                ;;
        esac
    done
}

# =========[ Main Menu Loop ]=========

# Present the main user interface and handle user input
while true; do
    echo "                                                  "
    echo " _____         _      _____         _ _           "
    echo "|  _  |___ ___| |_   |     |___ ___|_| |_ ___ ___ "
    echo "|   __| . |  _|  _|  | | | | . |   | |  _| . |  _|"
    echo "|__|  |___|_| |_|    |_|_|_|___|_|_|_|_| |___|_|  "
    echo "                                                  "
    echo "   Scan Menu"
    echo "   ==================="
    echo "1. One-Time Scan"
    echo "2. Recurring Scan"
    echo "3. Stop Recurring Scan"
    echo "4. Help"
    echo "5. Exit"
    echo ""
    echo "Note:"
    echo "- To change your port range go to the Help menu (#4)"
    echo "- Your msmtp config file: ~/.msmtprc"
    read -p "Select an option (1-5): " option

    case $option in
        1)
            one_time_scan
            ;;
        2)
            recurring_scan
            ;;
        3)
            stop_recurring
            ;;
        4)
            show_help
            ;;
        5)
            echo "                                   "   
            echo "  _____           _ _              "
            echo " |   __|___ ___ _| | |_ _ _ ___    "
            echo " |  |  | . | . | . | . | | | -_|   "
            echo " |_____|___|___|___|___|_  |___|   "
            echo "                       |___|       "


            exit
            ;;
        9)
            # Easter Egg #2 (Art)
            echo "\."
            echo " \\\\      ."
            echo "  \\\\ _,.+;)_"
            echo "  .\\\\;~%:88%%."
            echo " (( a   \`)9,8;%%."
            echo " /\`   _) ' \`9%%%?"
            echo "(' .-' j    '8%%'"
            echo " \`\"+   |    .88%)+._____..,,_   ,+%$%."
            echo "       :.   d%9\`             \`-%*\"'~%$."
            echo "    ___(   (%C                 \`.   68%%9"
            echo "  .\"        \\7                  ;  C8%%)\`"
            echo "  : .\"-.__,'.____________..,\`   L.  \\86' ,"
            echo "  : L    : :            \`  .'\.   '.  %$9%)"
            echo "  ;  -.  : |             \\  \\  \"-._ \`. \`~\""
            echo "   \`. !  : |              )  >     \". ?"
            echo "     \`'  : |            .' .'       : |"
            echo "         ; !          .' .'         : |"
            echo "        ,' ;         ' .'           ; ("
            echo "       .  (         j  (            \`  \\"
            echo "       \"\"\"'          \"\"'             \`\"\""
            ;;
        0)
            # Easter Egg #2 (Website)
            xdg-open "https://www.youtube.com/watch?v=xm3YgoEiEDc&ab_channel=10Hours" >/dev/null 2>&1 &
            ;;
        *)
            echo "Invalid option."
            ;;
    esac
done
# End of script