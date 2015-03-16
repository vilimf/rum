#!/bin/bash
#==============================================================================
# Manage FREERADIUS MySQL DB via CLI menu interface.
#==============================================================================
# title			:RADIUS_user_manager.sh
# description		:This script allows you to manage FREERADIUS MySQL DB.
# author		:Frantisek Vilim, vilimf@gmail.com
# date			:20150315
# version		:0.9    
# usage			:bash RADIUS_user_manager.sh [OTHER_DBs_IP]
# notes			:Update default parameters in init function.
# bash_version		:4.1.2(1)-release
# licence		:GNU GPL v3.0
#==============================================================================


# Read CLI parameters.
if [ "$#" -ge 1 ]; then
        ARG=("$@")
        ARGCOUNT=$#
else
        ARGCOUNT=$#
fi

# Default return CODE
ERRCODE=99

function init() {
	#DB variables
        local DBUSER=''
        local DBPASSWD=''
        local DBNAME='radius'
        local DBNASTABLE='nas'
	local DBRADCHECKTABLE='radcheck'
	local DBHOST[0]='localhost'
        local DBHOST[1]=''
        #Add hosts from CLI
	for (( I=0; I<$ARGCOUNT; I++ ))
        do
                DBHOST[I+2]=${ARG[I]}
        done
	local SSL='--ssl-ca=/etc/mysql/certificates/client/ca.pem --ssl-cert=/etc/mysql/certificates/client/client-cert.pem --ssl-key=/etc/mysql/certificates/client/client-key.pem'
	DBNUM=0

	local USER=''
	local PASSWD=''
	local SELECTUSERNAMES=''
	local SELECTUSERPARAM=''
	local ERR=''
	local REPLY=''
	local CHOICE=''
	local COUNT=''
	local SELECTEDUSER=''
	local SELECTNAS=''
	local NASIP=''
	local NASNAME=''
	local NASSECRET=''
	
	clear
# Check connection to all DBs and save their command into array.
	I=0
	J=0
	while [ "${DBHOST[I]}" ]
        do
                DB[I]="mysql -s -N -h ${DBHOST[I]} -u $DBUSER -p$DBPASSWD $SSL $DBNAME"
		if ! $(echo "exit" | ${DB[I]} 2> /dev/null); then
			echo "ERROR: Check login to DB at host \"${DBHOST[I]}\"!"
                	exit 1
		fi
		echo "Connection to DB on host \"${DBHOST[I]}\" checked!"
		I=$(($I+1))
		DBNUM=$I
	done
	menu
}

function menu() {
# Show menu.
        echo -e "\nPress ENTER..."
	read WAIT
	clear
	echo -e "\n-------------------------------------------------------------"
	echo " Choose action you want to do from the list below (0-9):"
	echo "-------------------------------------------------------------"
	echo -e "\n ---------------"
	echo -e "  USERS:"
        echo -e " ---------------"
	echo -e "\t(1) Add new RADIUS user."
	echo -e "\t() Deny RADIUS user."
	echo -e "\t() Allow RADIUS user."
	echo -e "\t(4) Show RADIUS users."
        echo -e "\t(5) Delete RADIUS user."
        echo -e "\n ---------------"
	echo -e "  NASs:"
        echo -e " ---------------"
        echo -e "\t(6) Add new NAS."
        echo -e "\t(7) Show NASs."
        echo -e "\t(8) Delete NAS."
        echo -e "\n ---------------"
	echo -e "  DBs:"
        echo -e " ---------------"
        echo -e "\t(9) Synchronize all DBs from localhost."
	echo -e "\n ------------------------"
	echo -e "  (0) Exit!"
        echo -e " ------------------------\n"
	echo "Your choice:"
	read CHOICE
	if [ -z "$CHOICE" ]; then
		echo -e "ERROR: Selection cannot be NULL!\n"
		menu
	fi
	case $CHOICE in
		1) add_user ;;
		2) ;;
		3) ;;
		4) show_users ;;
		5) delete_user ;;
                6) add_nas ;;
                7) show_nas ;;
                8) delete_nas ;;
		9) synchronize_dbs ;;
		0) clear; ERRCODE=0; exit $ERRCODE ;;
		*) echo -e "ERROR: You must choose only between listed values!\n"; menu ;;
	esac
}

function print_select_all_usernames() {
# $1 = DB ID
# return $SELECTUSERNAMES
        SELECTUSERNAMES=$(echo "SELECT username FROM $DBRADCHECKTABLE ORDER BY username;" | ${DB[$1]})
	echo -e "\nUsers in DB:"
	echo "=============="
	echo "$(echo  "$SELECTUSERNAMES" | nl | column -c 40)"
	echo -e "\n"
}


function get_user_with_parameters() {
# $1 = USER, $2 = DB ID
# return $SELECTUSERPARAM
	SELECTUSERPARAM=$(echo "SELECT username,attribute,op,value FROM $DBRADCHECKTABLE WHERE username='$1';" | ${DB[$2]})
}

function read_username() { 
# return $USER
	echo -e "\nNew Username:"
	read USER
	check_username $USER
}

function read_passwd() {
# return $PASSWD
	echo -e "\nNew Password:"
	read PASSWD
	if [ -z "$PASSWD" ]; then
		echo -e "ERROR: Password cannot be NULL!"
		read_passwd
	elif ! [[ "$PASSWD" =~ ^[a-zA-Z0-9@_\!#\.\+,\;-]{1,253}$ ]]; then
		echo -e "ERROR: Password could contain only allowed characters: a-z,A-Z,0-9,.,;@_!#+-"
		read_passwd
	fi
}

function check_username() {
# $1 = USER
	ERR=''
	if [ -z "$1" ]; then
		echo -e "ERROR: Username cannot be NULL!"
		ERR=1
	elif ! [[ "$1" =~ ^[a-zA-Z0-9@_\.-]{1,253}$ ]]; then
                echo -e "ERROR: Password could contain only allowed characters: a-z,A-Z,0-9,.,;@_!#+-"
                ERR=1
        else
	        get_user_with_parameters $1 0
		if [ "$SELECTUSERPARAM" ]; then
                	echo -e "ERROR: Username is alredy used!"
                	ERR=1
		fi
	fi
	[ "$ERR" ] && read_username
}

function write_user_into_db() {
# $1 = USER, $2 = ATTRIBUTE $3 = VALUE, $4 = DB ID
	if [ "$2" = "Cleartext-Password" ]; then
		echo "INSERT INTO radcheck VALUES ('','$1','MD5-Password',':=',MD5('$3'));" | ${DB[$4]} 
	elif [ "$2" ]; then
		echo "INSERT INTO radcheck VALUES ('','$1','$2',':=','$3');" | ${DB[$4]}
	else
		echo "ERROR: Username or Attribute is NULL!"
	fi
	user_control_select $1 $2 $3 $4
}

function user_control_select() {
# $1 = USER, $2 = ATTRIBUTE, $3 = VALUE, $4 = DB ID
	[ "$4" -eq 0 ] && clear
	get_user_with_parameters $1 $4
	if [ "$SELECTUSERPARAM" ]; then
		echo -e "\n==================================================================================================="
		echo -e "SUCCESSFUL: User \"$1\" successfuly added into DB on host \"${DBHOST[$4]}\":"
                echo -e "==================================================================================================="
		echo "$SELECTUSERPARAM"
                echo -e "==================================================================================================="
	else
		echo -e "\nERROR: Write into DB on host \"${DBHOST[$4]}\" hasn't been succesful!"
		echo "Do you want to try it again? (Y/n)"
		read REPLY
		[ -z "$REPLY" ] && REPLY='Y'
		if [ "$REPLY" = 'Y' ] || [ "$REPLY" = 'y' ]; then
			echo -e "\nTrying again..."
			write_user_into_db $1 $2 $3 $4
		else
	                echo -e "\nERROR: Write into DB on host \"${DBHOST[$4]}\" hasn't been succesful!"
			echo -e "\nNOTIFICATION: Continuing to the next server!"
		fi
	fi
}

function select_user() {
# $1 = DB ID
# resturn $count = count of users, $USER = selected user
	print_select_all_usernames $1
        COUNT=$(echo "$SELECTUSERNAMES" | wc -l)
        echo -e "Select user you want to delete (0-$COUNT, 0=Storno):"
        read CHOICE
        [ -z "$CHOICE" ] && echo -e "ERROR: Selection cannot be NULL!\n" || if ! [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
                echo "ERROR: You must insert ONLY number of the user!"
                select_user $1
        elif [ $CHOICE -ge 0 ] && [ $CHOICE -le $COUNT ]; then
                if [ $CHOICE = 0 ]; then
                        menu
                else
			USER=$(echo "$SELECTUSERNAMES" | sed -n ${CHOICE}p)
                        echo -e "\nAre you sure you want to delete user \"$USER\"? (y/N)"
                        read CHOICE
                        [ -z "$CHOICE" ] && REPLY='N'
                        if [ "$CHOICE" = 'Y' ] || [ "$CHOICE" = 'y' ]; then
				for ((I=0; I<$DBNUM; I++))
				do
					delete_selected_user $USER $I
				done
			else
                                echo -e "\nStorno."
                                select_user $1
                        fi

		fi
        else
                echo -e "ERROR: You must chose only from listed Users!"
                select_user $1
	fi
	select_user $1
}

function delete_selected_user() {
# $1 = USER, $2 = DB ID
	echo "DELETE FROM $DBRADCHECKTABLE where username='$1';" | ${DB[$2]}
	get_user_with_parameters $1 $2
	if [ $2 -eq 0 ]; then
		clear
	fi
	if [ "$SELECTUSER" ]; then
                echo -e "\n==================================================================================================="
		echo "ERROR: User \"$1\" hasn\'t been deleted from host \"${DBHOST[$2]}\"."
                echo -e "==================================================================================================="
	else
                echo -e "\n==================================================================================================="
		echo "SUCCESSFUL: User \"$1\" successfuly deleted from host \"${DBHOST[$2]}\"."
                echo -e "==================================================================================================="
	fi
}

function read_nasip() {
#  return $NASIP
	ERR=''
	echo -e "\nNew NAS IP:"
        read NASIP
	if ! [[ "$NASIP" =~ (25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?) ]]; then
		echo "ERROR: You must enter valid IP address."
		ERR=1
	else
		select_nas_with_parameters $NASIP 0
		if [ "$SELECTNAS" ]; then
			echo "ERROR: NAS IP already used!"
			ERR=1
		fi
	fi
	if [ "$ERR" ]; then
		read_nasip
	fi
}

function read_nasname() {
# return $NASNAME
        echo -e "\nNew NAS name:"
        read NASNAME
	if [ -z "$NASNAME" ]; then
		echo -e "ERROR: NAS name cannot be NULL!"
		read_nasname
	fi
}

function read_nassecret() {
# return $NASSECRET
        echo -e "\nNew NAS secret:"
        read NASSECRET
        if [ -z "$NASSECRET" ]; then
		echo -e "ERROR: NAS secret cannot be NULL!"
		read_nassecret
	fi
}

function select_nas_with_parameters() {
# $1 = NASIP, $2 = DB ID
# return $SELECTNAS
        SELECTNAS=$(echo "SELECT nasname,shortname,secret FROM $DBNASTABLE WHERE nasname='$1';" | ${DB[$2]})
}

function write_nas() {
# $1 = NASIP, $2 = NASNAME, $3 = NASSECRET, $4 = DB ID
        if [ "$1" ] && [ "$2" ] && [ "$3" ]; then
		echo "INSERT INTO nas VALUES ('','$1','$2','','','$3','','','');" | ${DB[$4]}
	fi
        nas_control_select $1 $2 $3 $4
}

function nas_control_select() {
# $1 = NASIP, $2 = NASNAME, $3 = NASSECRET, $4 = DB ID
        select_nas_with_parameters $1 $4
	if [ "$4" -eq 0 ]; then
		clear
	fi
        if [ "$SELECTNAS" ]; then
                echo -e "\n==================================================================================================="
                echo -e "SUCCESSFUL: NAS \"$2\" successfuly added into DB on host \"${DBHOST[$4]}\":"
                echo -e "==================================================================================================="
                echo "$SELECTNAS"
                echo -e "==================================================================================================="
        else
                echo -e "\nERROR: Write into DB hasn't been succesful on host \"${DBHOST[$4]}\"!"
                echo "Do you want to try it again? (Y/n)"
                read REPLY
                [ -z "$REPLY" ] && REPLY='Y'
                if [ "$REPLY" = 'Y' ] || [ "$REPLY" = 'y' ]; then
                        echo -e "\nTrying again..."
                        write_nas $1 $2 $3 $4
                else
                	echo -e "\nERROR: Write into DB hasn't been succesful on host \"${DBHOST[$4]}\"!"
                        echo -e "\nNOTIFICATION: Continuing to the next server!"
		fi
        fi
}

function print_select_all_nas() {
# $1 = DB ID
# return $SELECTNAS
        SELECTNAS=$(echo "SELECT shortname,nasname FROM $DBNASTABLE ORDER BY shortname;" | ${DB[$1]})
        echo -e "\nNASs in DB:"
        echo "=============="
        echo "$(echo "$SELECTNAS" | nl)"
        echo -e "\n"
}

function select_nas() {
# return $COUNT = count of NAS, $NASIP = selected nas IP
        print_select_all_nas 0
        COUNT=$(echo "$SELECTNAS" | wc -l)
        echo -e "Select NAS you want to delete (0-$COUNT, 0=Storno):"
        read CHOICE
        [ -z "$CHOICE" ] && echo -e "ERROR: Selection cannot be NULL!\n" || if ! [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
                echo "ERROR: You must insert ONLY number of the NAS!"
                select_nas 
        elif [ $CHOICE -ge 0 ] && [ $CHOICE -le $COUNT ]; then
                if [ $CHOICE = 0 ]; then
                        menu
                else
                        NASIP=$(echo "$SELECTNAS" | sed -n ${CHOICE}p | awk '{print $2}' )
                        echo -e "\nAre you sure you want to delete NAS \"$NASIP\"? (y/N)"
                        read CHOICE
                        [ -z "$CHOICE" ] && REPLY='N'
                        if [ "$CHOICE" = 'Y' ] || [ "$CHOICE" = 'y' ]; then
				for ((I=0; I<DBNUM; I++))
				do
                                	delete_selected_nas $NASIP $I
				done
                        else
                                echo -e "\nStorno."
                                select_nas
                        fi
                fi
        else
                echo -e "ERROR: You must chose only from listed NASs!"
                select_nas
        fi
        select_nas
}

function delete_selected_nas() {
# $1 = NASIP, $2 = DB ID
	echo "DELETE FROM $DBNASTABLE WHERE nasname='$1';" | ${DB[$2]}
        select_nas_with_parameters $1 $2
        if [ $2 -eq 0 ]; then
		clear
	fi
	if [ "$SELECTNAS" ]; then
	        echo -e "\nERROR: Write into DB hasn't been succesful on host \"${DBHOST[$2]}\"!"
                echo "Do you want to try it again? (Y/n)"
                read REPLY
                [ -z "$REPLY" ] && REPLY='Y'
                if [ "$REPLY" = 'Y' ] || [ "$REPLY" = 'y' ]; then
                        echo -e "\nTrying again..."
                        delete_selected_nas $1 $2
                else
                        echo -e "\nERROR: Write into DB hasn't been succesful on host \"${DBHOST[$2]}\"!"
                        echo -e "\nNOTIFICATION: Continuing to the next server!"
                fi

	else
                echo -e "\n==================================================================================================="
                echo "SUCCESSFUL: NAS \"$1\" successfuly deleted on host \"${DBHOST[$2]}\"."
                echo -e "==================================================================================================="
	fi
}

function find_differences_nas() {
# $1 = SOURCE DB, $2 = TARGET DB
# return $LOCAL = local DB, $REMOTE = remote DB, $DIFFERENCE = difference between tables, $COUNT = number of different lines
	LOCAL=$(echo "SELECT nasname,shortname,ports,secret FROM $DBNASTABLE ORDER BY nasname;" | ${DB[$1]})
	REMOTE=$(echo "SELECT nasname,shortname,ports,secret FROM $DBNASTABLE ORDER BY nasname;" | ${DB[$2]})
	DIFFERENCE=$(diff -u  <(echo "$REMOTE") <(echo "$LOCAL") | sed -n '/^[+-][0-9]/p')
	COUNT=$(echo "$DIFFERENCE" | wc -l)
}

function synchronize_nas_differences() {
# $1 = SOURCE DB, $2 = TARGET DB
        if [ "$DIFFERENCE" ]; then
		for ((J=1; J<=$COUNT; J++))
		do
			SIGN=$(echo "$DIFFERENCE" | sed -n ${J}p | cut -c 1 )
			NASIP=$(echo "$DIFFERENCE" | sed -n ${J}p | cut -c 2- | awk '{print $1}')
			NASNAME=$(echo "$DIFFERENCE" | sed -n ${J}p | cut -c 2- | awk '{print $2}')
			NASSECRET=$(echo "$DIFFERENCE" | sed -n ${J}p | cut -c 2- | awk '{print $4}')
			if [ "$SIGN" = '+' ]; then
				write_nas $NASIP $NASNAME $NASSECRET $2
			elif [ "$SIGN" = '-' ]; then
				delete_selected_nas $NASIP $2
			else
				echo "FAIL!"
			fi
		done
		find_differences_nas $1 $2
		if [ "$DIFFERENCE" ]; then
	                echo -e "\n==================================================================================================="
                	echo "ERROR: Synchronization from \"${DBHOST[$1]}\" to \"${DBHOST[$2]}\" hasn't been successfull!"
	                echo -e "==================================================================================================="
		else
                        echo -e "\n==================================================================================================="
	        	echo "SUCCESSFULL: Synchronization from \"${DBHOST[$1]}\" to \"${DBHOST[$2]}\" has been successfull!"
	                echo -e "==================================================================================================="
		fi
	else
		echo -e "\n==================================================================================================="
		echo "NOTIFICATION: NAS tables in DBs on hosts \"${DBHOST[$1]}\" and \"${DBHOST[$2]}\" are and were same."
                echo -e "==================================================================================================="
	fi
}

function find_differences_radcheck() {
# $1 = SOURCE DB, $2 = TARGET DB
# return $LOCAL = local DB, $REMOTE = remote DB, $DIFFERENCE = difference between tables, $COUNT = number of different lines
        LOCAL=$(echo "SELECT username,attribute,op,value FROM $DBRADCHECKTABLE ORDER BY username;" | ${DB[$1]})
	REMOTE=$(echo "SELECT username,attribute,op,value FROM $DBRADCHECKTABLE ORDER BY username;" | ${DB[$2]})
	DIFFERENCE=$(diff -u  <(echo "$REMOTE") <(echo "$LOCAL") | sed -n '/^[+-][^+-]/p')
        COUNT=$(echo "$DIFFERENCE" | wc -l)
}

function synchronize_radcheck_differences() {
# $1 = SOURCE DB, $2 = TARGET DB
        if [ "$DIFFERENCE" ]; then
                for ((J=1; J<=$COUNT; J++))
                do
                        SIGN=$(echo "$DIFFERENCE" | sed -n ${J}p | cut -c 1 )
                        USER=$(echo "$DIFFERENCE" | sed -n ${J}p | cut -c 2- | awk '{print $1}')
                        ATTRIBUTE=$(echo "$DIFFERENCE" | sed -n ${J}p | cut -c 2- | awk '{print $2}')
                        VALUE=$(echo "$DIFFERENCE" | sed -n ${J}p | cut -c 2- | awk '{print $4}')
                        if [ "$SIGN" = '+' ]; then
                        	write_user_into_db $USER $ATTRIBUTE $VALUE $2
			elif [ "$SIGN" = '-' ]; then
				delete_selected_user $USER $2
                        else
                                echo "FAIL!"
                        fi
                done
                find_differences_radcheck $1 $2
                if [ "$DIFFERENCE" ]; then
        	        echo -e "\n==================================================================================================="
                        echo "ERROR: Synchronization from \"${DBHOST[$1]}\" to \"${DBHOST[$2]}\" hasn't been successfull!"
	                echo -e "==================================================================================================="
                else
                        echo -e "\n==================================================================================================="
		        echo "SUCCESSFULL: Synchronization from \"${DBHOST[$1]}\" to \"${DBHOST[$2]}\" has been successfull!"
	                echo -e "==================================================================================================="
                fi
        else
                echo -e "\n==================================================================================================="
                echo "NOTIFICATION: RADCHECK tables in DBs on hosts \"${DBHOST[$1]}\" and \"${DBHOST[$2]}\" are and were same."
                echo -e "==================================================================================================="
        fi
}

function show_nas() {
        clear
        print_select_all_nas
        menu
}

function add_nas() {
	clear
        read_nasip
	read_nasname
	read_nassecret
	for ((I=0; I<$DBNUM; I++))
	do
		write_nas $NASIP $NASNAME $NASSECRET $I
	done
	menu
}

function delete_nas() {
        clear
        select_nas
}

function add_user()
{
	clear
	read_username
	read_passwd
	for ((I=0; I<$DBNUM; I++))
	do
		write_user_into_db $USER Cleartext-Password $PASSWD $I
	done
	menu
}

function show_users() {
	clear
	print_select_all_usernames 0
	menu
}

function delete_user() {
	clear
	select_user 0
}

function synchronize_nas() {
        for ((I=0; I<$DBNUM; I++))
        do
                if ! [ $1 -eq $I ]; then
			find_differences_nas $1 $I
			synchronize_nas_differences $1 $I
		fi
        done
}

function synchronize_radcheck() {
        for ((I=0; I<$DBNUM; I++))
        do
                if ! [ $1 -eq $I ]; then
                        find_differences_radcheck $1 $I
                        synchronize_radcheck_differences $1 $I
                fi
        done
}

function synchronize_dbs() {
# synchronize DBs from localhost
	clear
	synchronize_nas 0
	synchronize_radcheck 0
	menu
}

init
