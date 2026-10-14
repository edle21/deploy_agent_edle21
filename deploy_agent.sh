#!/bin/bash


# the folder name we are working with (set when the user types a name)
proj_folder=""

# checks that python3 and zip are installed
check_tools() {
    if which python3 > /dev/null 2>&1; then
        python3 --version
    else
        echo "Error: python3 is not installed."
        exit 1
    fi
    if which zip > /dev/null 2>&1; then
        echo "zip is installed."
    else
        echo "Error: zip is not installed."
        exit 1
    fi
}

# runs on Ctrl+C or Ctrl+Z while deploying: zip it, delete it, then exit
handle_stop() {
    echo ""
    echo "Deployment was interrupted."
    if [ -d "$proj_folder" ]; then
        zip -r "$proj_folder"_archive.zip "$proj_folder" > /dev/null
        echo "Saved what was built into $proj_folder""_archive.zip"
        rm -rf "$proj_folder"
        echo "Removed the incomplete folder $proj_folder"
    else
        echo "Nothing was created yet, so nothing to zip."
    fi
    echo "Closing the script."
    exit 1
}

# asks for a number, keeps asking until it is valid
# before calling it, set question_text, low_limit, high_limit, default_value
ask_number() {
    number_ok="no"
    while [ "$number_ok" = "no" ]; do
        read -p "$question_text (default $default_value, press Enter to keep): " typed
        if [ -z "$typed" ]; then
            typed="$default_value"
        fi
        if echo "$typed" | grep '^[0-9][0-9]*$' > /dev/null; then
            if [ "$typed" -lt "$low_limit" ]; then
                echo "Number must be between $low_limit and $high_limit."
            elif [ "$typed" -gt "$high_limit" ]; then
                echo "Number must be between $low_limit and $high_limit."
            else
                number_ok="yes"
            fi
        else
            echo "That is not a number, try again."
        fi
    done
}

# asks how many students (1 to 10)
ask_student_count() {
    question_text="How many students (1-10)"
    low_limit=1
    high_limit=10
    default_value=10
    ask_number
    how_many="$typed"
}

# copies that many students from the template roster
copy_roster() {
    ask_student_count
    lines_needed=$(expr $how_many + 1)
    head -n $lines_needed templates/assets.csv > "$proj_folder/Helpers/assets.csv"
    echo "Copied $how_many students from the template."
}

# builds a new roster with counts of 0
make_roster() {
    ask_student_count
    echo "Email,Names,Attendance Count,Absence Count" > "$proj_folder/Helpers/assets.csv"
    row_count=0
    for first in Alice Bob Carol David Eve Frank Grace Henry Ivy Jack
    do
        if [ "$row_count" -lt "$how_many" ]; then
            echo "$first@example.com,$first Student,0,0" >> "$proj_folder/Helpers/assets.csv"
            row_count=$(expr $row_count + 1)
        fi
    done
    # new roster means this is session one
    sed -i 's/"total_sessions": 5/"total_sessions": 1/' "$proj_folder/Helpers/config.json"
    echo "Made $how_many students and set total_sessions to 1."
}

# asks if the user wants new thresholds and edits config.json with sed
change_thresholds() {
    read -p "Do you want to update the alert thresholds? (y/n): " want_change
    if [ "$want_change" = "y" ]; then
        question_text="Enter the warning threshold"
        low_limit=0
        high_limit=100
        default_value=75
        ask_number
        new_warning="$typed"

        question_text="Enter the failure threshold"
        default_value=50
        ask_number
        new_failure="$typed"

        sed -i "s/\"warning\": [0-9]*/\"warning\": $new_warning/" "$proj_folder/Helpers/config.json"
        sed -i "s/\"failure\": [0-9]*/\"failure\": $new_failure/" "$proj_folder/Helpers/config.json"
        echo "Thresholds updated: warning=$new_warning failure=$new_failure"
    else
        echo "Keeping the default thresholds."
    fi
}

# runs the python app inside the project folder
start_app() {
    if [ -d "$proj_folder" ]; then
        cd "$proj_folder"
        python3 attendance_checker.py
        cd ..
    else
        echo "Error: $proj_folder does not exist. Deploy it first."
    fi
}

# feature 1: deploy the whole project
deploy_project() {
    check_tools

    read -p "Enter a name for the project: " proj_name
    if [ -z "$proj_name" ]; then
        echo "Error: the name cannot be empty."
        return
    fi
    proj_folder="attendance_tracker_$proj_name"

    # handle a folder that already exists
    if [ -d "$proj_folder" ]; then
        read -p "$proj_folder already exists. Overwrite it? (y/n): " overwrite
        if [ "$overwrite" = "y" ]; then
            rm -rf "$proj_folder"
        else
            echo "Aborted. Nothing was changed."
            return
        fi
    fi

    # from here on, Ctrl+C and Ctrl+Z are caught
    trap handle_stop SIGINT SIGTSTP

    if mkdir -p "$proj_folder/Helpers" "$proj_folder/reports"; then
        echo "Folders created."
    else
        echo "Error: could not create folders. Check your permissions."
        trap - SIGINT SIGTSTP
        return
    fi

    cp templates/attendance_checker.py "$proj_folder/"
    cp templates/config.json "$proj_folder/Helpers/"
    if [ ! -f "$proj_folder/attendance_checker.py" ]; then
        echo "Error: could not copy attendance_checker.py."
        rm -rf "$proj_folder"
        trap - SIGINT SIGTSTP
        return
    fi
    if [ ! -f "$proj_folder/Helpers/config.json" ]; then
        echo "Error: could not copy config.json."
        rm -rf "$proj_folder"
        trap - SIGINT SIGTSTP
        return
    fi

    echo "How do you want to build the roster?"
    echo "A) copy from templates/assets.csv"
    echo "B) generate a new roster"
    read -p "Choose A or B: " roster_choice
    while [ "$roster_choice" != "A" ]
    do
        if [ "$roster_choice" = "B" ]; then
            break
        fi
        read -p "Please type A or B: " roster_choice
    done
    if [ "$roster_choice" = "A" ]; then
        copy_roster
    else
        make_roster
    fi

    chmod +x "$proj_folder/attendance_checker.py"
    chmod 600 "$proj_folder/Helpers/config.json"
    echo "Permissions set:"
    ls -l "$proj_folder/attendance_checker.py"
    ls -l "$proj_folder/Helpers/config.json"

    change_thresholds

    # deployment is done, stop catching signals
    trap - SIGINT SIGTSTP
    echo "Deployment finished. Running the app to check it works..."
    start_app
}

# feature 2: run an already deployed project
run_project() {
    check_tools
    read -p "Enter the project name: " proj_name
    proj_folder="attendance_tracker_$proj_name"
    start_app
}

# feature 3: copy the logs into the archives folders with a timestamp
archive_project() {
    read -p "Enter the project name: " proj_name
    proj_folder="attendance_tracker_$proj_name"
    if [ ! -d "$proj_folder" ]; then
        echo "Error: $proj_folder does not exist."
        return
    fi

    time_stamp=$(date +%Y%m%d_%H%M%S)
    mkdir -p "$proj_folder/archives/attendance"
    mkdir -p "$proj_folder/archives/absent"

    if [ -f "$proj_folder/reports/attendance.log" ]; then
        cp "$proj_folder/reports/attendance.log" "$proj_folder/archives/attendance/attendance_$time_stamp.log"
        echo "Archived: $proj_folder/archives/attendance/attendance_$time_stamp.log"
    else
        echo "attendance.log was not found, skipping it."
    fi

    if [ -f "$proj_folder/reports/absent.log" ]; then
        cp "$proj_folder/reports/absent.log" "$proj_folder/archives/absent/absent_$time_stamp.log"
        echo "Archived: $proj_folder/archives/absent/absent_$time_stamp.log"
    else
        echo "absent.log was not found (maybe nobody was absent), skipping it."
    fi
}

# main menu that keeps repeating until the user quits
menu_choice=""
while [ "$menu_choice" != "4" ]
do
    echo ""
    echo "===== Deploy Agent ====="
    echo "1) Deploy the application"
    echo "2) Run the application"
    echo "3) Archive the log files"
    echo "4) Quit"
    read -p "Pick an option: " menu_choice
    if [ "$menu_choice" = "1" ]; then
        deploy_project
    elif [ "$menu_choice" = "2" ]; then
        run_project
    elif [ "$menu_choice" = "3" ]; then
        archive_project
    elif [ "$menu_choice" = "4" ]; then
        echo "Goodbye."
    else
        echo "Please pick 1, 2, 3 or 4."
    fi
done
