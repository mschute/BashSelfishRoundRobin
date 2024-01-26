#!/bin/bash

declare -a standby_queue
declare -a new_queue
declare -a accepted_queue

declare -a names
declare -a services
declare -a arrivals
declare -a priorities
declare -a statuses

declare -i system_time
declare -i quanta_time

declare data_file
declare new_increment
declare accepted_increment
declare quanta

declare -i is_accepted_empty

function Test_Given_Parameters {
    data_file=$1
    new_increment=$2
    accepted_increment=$3
    quanta=1

    if [[ ($# -lt 3 || $# -gt 4) ]]; then
        echo "Error: Expected 3 or 4 parameters. Received $#. Please try again."
        exit
    fi

    if [ -d "${data_file}" ]; then
        echo "Error: Expected regular file. Received \"${data_file}\" directory instead."
        exit
    fi

    if [ ! -f "$data_file" ]; then
        echo "Error: File does not exist. Please try again."
        exit
    fi

    if [ $# -gt 3 ]; then
        quanta=$4
    fi

    if [ "$4" != "" ]; then
        if [[ $((quanta)) != "$quanta" ]]; then
            echo "Error: Expected integer for quanta. Received $4. Please try again."
            exit
        fi
    fi

    if [ $((quanta)) -lt 0 ]; then
        echo "Error: Expected positive integer for quanta value. Received $4. Please try again."
        exit
    fi

    if [[ $((new_increment)) != "$new_increment" ]]; then
        echo "Error: Expected integer for new queue increment value. Received $2. Please try again."
        exit
    fi

    if [ "$2" -lt 0 ]; then
        echo "Error: Expected positive integer for new queue increment value. Received $2. Please try again."
        exit
    fi

    if [ $((accepted_increment)) != "$accepted_increment" ]; then
        echo "Error: Expected integer for accepted queue increment value. Received $3. Please try again."
        exit
    fi

    if [ "$3" -lt 0 ]; then
        echo "Error: Expected positive integer for accepted queue increment value. Received $3. Please try again."
        exit
    fi
}

function getFileName() {
    echo "State the name of the file you wish to output to: \c"
    read -r output_file_name

    while [ -f "$output_file_name" ]; do
        echo "\n$output_file_name already exists."
        echo "Would you like to overwrite it? y or n"
        read -r overwrite_answer
        if [ "${overwrite_answer}" = "y" ]; then
            printf "" >"$output_file_name"
            break
        else
            echo "State the name of the file you wish to output to: \c"
            read -r output_file_name
        fi
    done
}

function Output_Standard() {
    $1
}

function Output_File() {
    $1 >>$output_file_name
}

function Output_Both() {
    Output_Standard $1
    Output_File $1
}

function Set_Output_Mode {
    declare -i user_answer

    while [[ (user_answer -lt 1 || user_answer -gt 3) ]]; do
        printf "\nHow would you like to output the results?\n"
        echo "Enter 1 for standard output"
        echo "Enter 2 for file output"
        echo "Enter 3 for both"
        read -r user_answer
    done

    if [ "$user_answer" == "1" ]; then
        output_function="Output_Standard"
    elif [ "$user_answer" == "2" ]; then
        getFileName
        output_function="Output_File"
    elif [ "$user_answer" == "3" ]; then
        getFileName
        output_function="Output_Both"
    fi
}

function Process_Data_Row() {
    if [ $# != "4" ]; then
        echo "Error: Invalid data. Expected 4 parameters. Received $#. Please verify your data file."
        exit
    fi

    local -i index
    local service
    local arrival

    index=$1
    name=$2
    service=$3
    arrival=$4

    if [[ $((service)) != "$service" ]]; then
        echo "Error: Expected integer for service value. Received $service. Please check your data."
        exit
    fi

    if [ "$service" -lt 0 ]; then
        echo "Error: Service must be an integer >= 0, received $service. Please check your data."
        exit
    fi

    if [[ $((arrival)) != "$arrival" ]]; then
        echo "Error: Expected integer for arrival value. Received $arrival. Please check your data."
        exit
    fi

    if [ "$arrival" -lt 0 ]; then
        echo "Error: Arrival time must be an integer >=0, received $arrival. Please check your data."
        exit
    fi

    standby_queue[index]="$index"
    names[index]="$name"
    services[index]="$service"
    arrivals[index]="$arrival"
    statuses[index]="-"
    priorities[index]=0
}

function Read_Data_From_File {
    local -i i # (Rahul, 2023)
    i=0
    while IFS= read -r line; do #(RIP Tutorial, no date)
        Process_Data_Row $i $line
        ((i += 1))
    done <"$data_file"
}

function Highest_Name_Length {
    local -i highest_count # (Rahul, 2023)
    # Set highest count to 4 to account for "Time" label
    highest_count=4
    for ((i = 0; i < ${#names[*]}; i++)); do # (Gite, 2023b; SteveP, 2013)
        # If the char count in the next string is greater than current highest count, save over it
        if [ "$highest_count" -lt ${#names[i]} ]; then
            highest_count=${#names[i]}
        fi
    done
    return "$highest_count"
}

function Print_Output_Labels {
    printf "%-${name_count}s " "Time"
    printf "%-${name_count}s " "${names[@]}" # (Smotricz, 2009; Linuxize, 2020; Gite, 2023a)
    printf "\n"
}

function Check_Finished_Status {
    for ((i = 0; i < ${#statuses[*]}; i++)); do # (Gite, 2023b)
        if [ "${statuses[i]}" != "F" ]; then
            return 0
        fi
    done
    return 1
}

function Update_Accepted_Flag_If_Empty {
    if [ "${#accepted_queue[*]}" == 0 ]; then # (Charalambous, 2023b)
        is_accepted_empty=1
    else
        is_accepted_empty=0
    fi
}

function Remove_Standby_Queue_Value() {
    local -i index # (Rahul, 2023)
    # Setting to index -1 so it throws an error if parameter was not saved to index
    index=$((-1))

    # Functions can't return array so operate on global variable instead
    # (CybeX, 2015)
    length=${#standby_queue[*]}

    # Find index in standby queue of process ID that needs to be removed
    for i in "${!standby_queue[@]}"; do # (Jackman, 2011; Meetgor, 2022; Gite, 2023a)
        if [ "${standby_queue[$i]}" == "$1" ]; then
            index=$i
            break
        fi
    done

    # Check if index is original value, if so, exit
    if [ $index -lt 0 ]; then
        return
    fi

    # Check if index is out of bounds, if so, exit
    if [ $index -gt $((length - 1)) ]; then # (Charalambous, 2023b)
        return
    fi

    # Find length of first section of the array before the process ID to be removed
    start1=0
    length1=$((index)) # (Charalambous, 2023b)

    # Find length of second section of the array after the process ID to be removed
    start2=$((index + 1))
    length2=$((length - start2)) # (Charalambous, 2023b)

    # If the ID to be removed is first element, only keep second section of array
    if [ $index == 0 ]; then
        standby_queue=("${standby_queue[*]:$start2:$length2}") # (Charalambous, 2023b)
        return
    fi

    # If the ID to be removed is last element, only keep first section of array
    if [ $index == "$length" ]; then
        standby_queue=("${standby_queue[*]:$start1:$length1}") # (Charalambous, 2023b)
        return
    fi

    # Save the two sections of the array around the removed value into separate arrays
    array1=("${standby_queue[*]:$start1:$length1}") # (Charalambous, 2023b)
    array2=("${standby_queue[*]:$start2:$length2}") # (Charalambous, 2023b)

    # Combining two arrays into the original array
    standby_queue=("${array1[@]}" "${array2[@]}") # (Heath Borders, 2016)
}

function Process_Arrivals {
    for id in "${!arrivals[@]}"; do
        if [ "${arrivals[$id]}" == $system_time ]; then

            Remove_Standby_Queue_Value "$id"
            if [ $is_accepted_empty -eq 1 ]; then
                accepted_queue+=("${id}")
            else
                new_queue+=("${id}")
            fi

            statuses[id]="W"
            priorities[id]=0
        fi
    done
}

function Increment_Accepted_Queue_Priority {
    for aid in "${accepted_queue[@]}"; do
        priorities[aid]=$((priorities[aid] + accepted_increment))
    done
}

function Increment_New_Queue_Priority {
    for nid in "${new_queue[@]}"; do
        priorities[nid]=$((priorities[nid] + new_increment))
    done
}

function Shift_Accepted_Queue {
    accepted_queue=("${accepted_queue[@]:1}")
    quanta_time=0
}

function Matches_Priority {
    local -i priority
    priority=$1

    if [ ${#accepted_queue[*]} -lt 1 ]; then
        return 1
    fi

    for pID in "${accepted_queue[@]}"; do
        if [ "${priority}" -gt $((priorities[pID] - 1)) ]; then
            return 1
        fi
    done

    return 0
}

function Move_New_To_Accepted {
    while [ ${#new_queue[*]} -gt 0 ]; do
        id=${new_queue[0]}
        priority=${priorities[$id]}

        Matches_Priority "$priority"
        matches=$?

        if [ $matches == 1 ]; then
            new_queue=("${new_queue[@]:1}")
            accepted_queue+=("$id")
        else
            break
        fi
    done
}

function Process_Accepted_Queue {
    if [ ${#accepted_queue[*]} -gt 0 ]; then
        id=${accepted_queue[0]}

        if [ "${services[id]}" -lt 1 ]; then
            statuses[id]="F"
        fi

        if [ "${statuses[id]}" == "F" ]; then
            Shift_Accepted_Queue
            Move_New_To_Accepted
        elif [ $((quanta_time % quanta)) == 0 ]; then
            Shift_Accepted_Queue
            accepted_queue+=("$id")
            statuses[id]="W"
        fi
    fi
}

function Service_First_In_Accepted {
    if [ ${#accepted_queue[*]} -gt 0 ]; then
        id=${accepted_queue[0]}
        services[id]=$((services[id] - 1))
    fi
}

function Set_Top_Process_To_Running {
    if [ ${#accepted_queue[*]} -gt 0 ]; then
        id=${accepted_queue[0]}
        statuses[id]="R"
    fi
}

function Output_Status {
    printf "%-${name_count}s " "$system_time"
    printf "%-${name_count}s " "${statuses[@]}"
    printf "\n"
}

function Increment_Quanta_Time {
    quanta_time=$((quanta_time + 1))
}

function Increment_System_Time {
    system_time=$((system_time + 1)) # (Charalambous, 2023b)
}

printf "\nWelcome to Selfish Round Robin\n\n"

Test_Given_Parameters "$@"

Read_Data_From_File

printf "The data you are using is: \n"
cat "$1"

Highest_Name_Length
name_count=$?

Set_Output_Mode

printf "\n"
${output_function} Print_Output_Labels

quanta_time=0
system_time=0
is_accepted_empty=1

while Check_Finished_Status; do
    Update_Accepted_Flag_If_Empty
    Process_Arrivals
    Move_New_To_Accepted
    Process_Accepted_Queue
    Service_First_In_Accepted
    Set_Top_Process_To_Running
    Increment_Accepted_Queue_Priority
    Increment_New_Queue_Priority

    ${output_function} Output_Status

    Increment_Quanta_Time
    Increment_System_Time
done

exit
