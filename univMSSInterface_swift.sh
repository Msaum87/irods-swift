#!/bin/bash

## Copyright (c) 2009 Data Intensive Cyberinfrastructure Foundation. All rights reserved.
## For full copyright notice please refer to files in the COPYRIGHT directory
## Written by Jean-Yves Nief of CCIN2P3 and copyright assigned to Data Intensive Cyberinfrastructure Foundation

# This script is a template which must be updated if one wants to use the universal MSS driver.
# Your working version should be in this directory server/bin/cmd/univMSSInterface.sh.
# Functions to modify: syncToArch, stageToCache, mkdir, chmod, rm, stat
# These functions need one or two input parameters which should be named $1 and $2.
# If some of these functions are not implemented for your MSS, just let this function as it is.
#


####################################
#TO-DO
#Break into 5GB Max chunks (because object storage)
#Check if exists, adjust name if needed (because object storage)
#maybe use md5sum as unique name for all storage on object side? also for integrity checks on sync/stage?

####################################
#Change Log
#2017-AUG-10::Created. Updated. Modified. And tested. syncToArch and stageToCache complete. Logging complete. Debug complete. Logging for mkdir and chmod in case they are used.
#2017-AUG-11::Delete finished
#2017-AUG-28::stat command data extraction from HTTP headers is completed

####################################
#Pre-defined environmental variables
#These are used in every session
####################################

PROG=$(basename $0)
TS=$(date +"%Y:%m:%d-%T")

#DEBUG Values:
#0 is no logging
#1 is errors only
#2 is every action
DEBUG=2

#logfile
LOGFILE="/home/irods/univSwift.log"

#token auth file for storing the Keystone token, and tracking age.
AUTH=$(</home/irods/swiftauth.txt)

#Storage URL (with container) ex: "swift.storage.com/irods"
#Preferential writing- i leave the trailing "/" off of this to use it below
#this lets me separate my URL from my object-cache name with the "/" in scripts
URL=$(</home/irods/swifturl.txt)

#Pulling our curl command
CURLCMD=$(which curl)


# function for the synchronization of file $1 on local disk resource to file $2 in the MSS
syncToArch () {
	# <your command or script to copy from cache to MSS> $1 $2
	# e.g: /usr/local/bin/rfcp $1 rfioServerFoo:$2
	
	#this pulls the directory hierarchy 
	meta=$(echo $1 | rev | cut -d '/' -f 2- | rev)
	#this gives us only the file name
	destFile=$(echo $2 | rev | cut -d '/' -f 1 | rev)
	#This is our function running
	cmdstat=$($CURLCMD -s -S -T $1 -X PUT -H "$AUTH" $URL/$destFile 2>&1)
	_log  syncToArch $? "$cmdstat" "$CURLCMD -s -S -T $1 -X PUT -H \"$AUTH\" $URL/$destFile"
	metastat=$($CURLCMD -s -S -X POST -H "$AUTH" $URL/$destFile -H "X-Object-Meta-collection: $meta" 2>&1)
	_log  syncToArch $? "$metastat" "$CURLCMD -s -S -X POST -H \"$AUTH\" $URL/$destFile -H \"X-Object-Meta-collection: $meta\""
	
	return
}

# function for staging a file $1 from the MSS to file $2 on disk
stageToCache () {
	# <your command to stage from MSS to cache> $1 $2
	# e.g: /usr/local/bin/rfcp rfioServerFoo:$1 $2
	
	#pulls the source file name only
	srcFile=$(echo $1 | rev | cut -d '/' -f 1 | rev)
	
	#pulls stored directory heirarcy
	meta=$($CURLCMD -s -S -X GET -H "$AUTH" $URL/$srcFile -I | grep -i meta-collection | awk '{print $2}' | tr -d '\r\n' )
	_log stageToCache $? "Pulling meta data for original hierarchy: $meta" "$CURLCMD -X GET -H \"$AUTH\" $URL/$srcFile -I | grep -i meta-collection | awk '{print $2}' | tr -d '\r\n'"
	mkstat=$(mkdir -p $meta 2>&1)
	_log stageToCache $? "$mkstat" "mkdir -p $meta"
	cmdstat=$($CURLCMD -s -S -X GET -H "$AUTH" $URL/$srcFile -o $meta/$srcFile 2>&1)
	_log stageToCache $? "$cmdstat" "$CURLCMD -X GET -H \"$AUTH\" $URL/$srcFile -o $meta/$srcFile "
	return
}


# function to create a new directory $1 in the MSS logical name space
mkdir () {
	# <your command to make a directory in the MSS> $1
	# e.g.: /usr/local/bin/rfmkdir -p rfioServerFoo:$1
	
	op=`which mkdir`
	cmdstat=$($op -p $1 2>&1)
	_log mkdir $? "$cmdstat" "Shouldn't be using mkdir commands in object storage. It is flat. Probably caused errors here"
	return
}

# function to modify ACLs $2 (octal) in the MSS logical name space for a given directory $1
chmod () {
	# <your command to modify ACL> $2 $1
	# e.g: /usr/local/bin/rfchmod $2 rfioServerFoo:$1
	############
	# LEAVING THE PARAMETERS "OUT OF ORDER" ($2 then $1)
	#	because the driver provides them in this order
	# $2 is mode
	# $1 is directory
	############
	op=`which chmod`
	cmdstat=$($op $2 $1 2>&1) 
	_log mkdir $? "$cmdstat" "Shouldn't be using chmod commands in object storage. iRODS owns the whole container anyway."
	return
}

# function to remove a file $1 from the MSS
rm () {
	# <your command to remove a file from the MSS> $1
	# e.g: /usr/local/bin/rfrm rfioServerFoo:$1
	cmdstat=$($CURLCMD -s -S -X DELETE -H "$AUTH" $URL/$1 2>&1)
	_log rm $? "$cmdstat" "$CURLCMD -X DELETE -H \"$AUTH\" $URL/$1"
	return
}

# function to rename a file $1 into $2 in the MSS
mv () {
	# <your command to rename a file in the MSS> $1 $2
	# e.g: /usr/local/bin/rfrename rfioServerFoo:$1 rfioServerFoo:$2
	op=`which mv`
	`$op $1 $2`
	return
}

# function to do a stat on a file $1 stored in the MSS
stat () {
	#This pulls the header stat info from curl. The "tr" removes the carriage returns and newlines, replacing them with spaces.
	output=$($CURLCMD -I -X GET -H "$auth" $url/sync.sh -s | tr '\r\n' ' ')
	_log stat $? "$CURLCMD -I -X GET -H "$auth" $url/sync.sh -s | tr '\r\n' ' '"
	# <your command to retrieve stats on the file> $1
	# e.g: output=`/usr/local/bin/rfstat rfioServerFoo:$1`
	# parse the output.
	# Parameters to retrieve: device ID of device containing file("device"),
	#			 file serial number ("inode"), ACL mode in octal ("mode"),
	#			 number of hard links to the file ("nlink"),
	#			 user id of file ("uid"), group id of file ("gid"),
	#			 device id ("devid"), file size ("size"), last access time ("atime"),
	#			 last modification time ("mtime"), last change time ("ctime"),
	#			 block size in bytes ("blksize"), number of blocks ("blkcnt")
	# e.g: device=`echo $output | awk '{print $3}'`
	# Note 1: if some of these parameters are not relevant, set them to 0.
	# Note 2: the time should have this format: YYYY-MM-dd-hh.mm.ss with:
	#					   YYYY = 1900 to 2xxxx, MM = 1 to 12, dd = 1 to 31,
	#					   hh = 0 to 24, mm = 0 to 59, ss = 0 to 59



	device=` echo $output | sed -nr 's/.*\<Device: *(\S*)\>.*/\1/p'`
	inode=`  echo $output | sed -nr 's/.*\<Inode: *(\S*)\>.*/\1/p'`
	mode="0"
	nlink="0"
	uid="0"
	gid="0"
	devid="0"
	size=$(echo $output | sed -nr 's/.*\Content-Length: *([0-9]*)\>.*/\1/p')
	blksize="0"
	blkcnt="0"
	#Pulls the acces timestamp info
	amonth=$(echo $output | sed -nr 's/.*\Date:......//p' | sed -nr 's/\GMT.*//p' | awk '{ print $2 } ')
    amonth=$(awk -v "month=$amonth" 'BEGIN {months = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec"; printf "%02d", (index(months, month) + 3) / 4}')
	aday=$(echo $output | sed -nr 's/.*\Date:......//p' | sed -nr 's/\GMT.*//p' | awk '{ print $1 } ')
	ayear=$(echo $output | sed -nr 's/.*\Date:......//p' | sed -nr 's/\GMT.*//p' | awk '{ print $3 } ')
	ats=$(echo $output | sed -nr 's/.*\Date:......//p' | sed -nr 's/\GMT.*//p' | awk '{ print $4 }' | tr ':' '.')
	atime=$(echo $ayear-$amonth-$aday-$ats)
	#pulls the last modified timestamp info
	mmonth=$(echo $output | sed -nr 's/.*\Last-Modified:......//p' | sed -nr 's/\GMT.*//p' | awk '{ print $2 } ')
	mmonth=$(awk -v "month=$mmonth" 'BEGIN {months = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec"; printf "%02d", (index(months, month) + 3) / 4}')
	mday=$(echo $output | sed -nr 's/.*\Last-Modified:......//p' | sed -nr 's/\GMT.*//p' | awk '{ print $1 } ')
	myear=$(echo $output | sed -nr 's/.*\Last-Modified:......//p' | sed -nr 's/\GMT.*//p' | awk '{ print $3 } ')
	mts=$(echo $output | sed -nr 's/.*\Last-Modified:......//p' | sed -nr 's/\GMT.*//p' | awk '{ print $4 }' | tr ':' '.')
	mtime==$(echo $myear-$mmonth-$mday-$mts)
	ctime=$(echo $mtime)
		
	echo "$device:$inode:$mode:$nlink:$uid:$gid:$devid:$size:$blksize:$blkcnt:$atime:$mtime:$ctime"
	_log stat $? "echo \"$device:$inode:$mode:$nlink:$uid:$gid:$devid:$size:$blksize:$blkcnt:$atime:$mtime:$ctime\""
	return
}
	

#################################################
#Helper Functions (logging & auth token handling)
#################################################


#Basic log call reads:
# which $1 function was called
# where $2 was the return value of the command
# where $3 was the return status text
# where $4 is a full syntax copy
# log calling looks like this:
# _log syncToArch $? $status "COMMAND SYNTAX"

_log() {

	if [ $(($DEBUG + $err)) -gt 1 ]
	then
		echo "$TS :: Function- $PROG $1 :: Returned- $2 :: Status- $3 :: Command- $4" >> $LOGFILE
	fi
}	
	
	


#############################################
# below this line, nothing should be changed.
#############################################

case "$1" in
	syncToArch ) $1 $2 $3 ;;
	stageToCache ) $1 $2 $3 ;;
	mkdir ) $1 $2 ;;
	chmod ) $1 $2 $3 ;;
	rm ) $1 $2 ;;
	mv ) $1 $2 $3 ;;
	stat ) $1 $2 ;;
esac

exit $?
