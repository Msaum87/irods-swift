#!/bin/sh

#set -x


## Copyright (c) 2009 Data Intensive Cyberinfrastructure Foundation. All rights reserved.
## For full copyright notice please refer to files in the COPYRIGHT directory
## Written by Jean-Yves Nief of CCIN2P3 and copyright assigned to Data Intensive Cyberinfrastructure Foundation

# This script is a template which must be updated if one wants to use the universal MSS driver.
# Your working version should be in this directory server/bin/cmd/univMSSInterface.sh.
# Functions to modify: syncToArch, stageToCache, mkdir, chmod, rm, stat
# These functions need one or two input parameters which should be named $1 and $2.
# If some of these functions are not implemented for your MSS, just let this function as it is.
#

# Changelog:
# 2013-01-22 - V1.00 - RV - initial version
# 2013-05-28 - v1.01 - RV - Add logging of universal MSS driver to logfile
# 2014-01-29 - v1.02 - RV - Add usage of gridftp for copy of files etc.
# 2014-02-07 - v1.03 - RV - Do NOT copy empty files in the function "syncToArch".
# 2014-02-07 - v1.04 - RV - Rework to use more and smaller readable functions.
# 2014-02-17 - v1.05 - RV - Add extra check to see if creation of directory really failed.
#			   We now use 4 ruleservers so it might be a race condition when a directory is created.
# 2015-07-01 - v1.06 - RV - implement copy of files with "," in filename.
# 2015-07-16 - v1.07 - RV - implement logging of error messages during copy with gridftp.
# 2015-08-10 - v1.08 - RV - implement retries from dCache to iRODS during copy with gridftp.
# 2015-10-14 - v1.09 - RV - implement stat function as it is being used in iRODS 4.1.6.
# 2015-10-20 - v1.10 - RV - implement stat function for gridftp. Before it was only a simple stat
# 2016-07-01 - v1.11 - RV - implement gridftp only script.

##################################
#This is Matthew Saum's modification of the UnivMSS driver to work with SWIFT storage and KeyStone Authentication.
#SURFsara
#######
#NOTES
#Create a file in the location of this script: "swiftauth.txt" and set permissions to 700
#We use this to track our 24hour auth token, pull another if needed, and import it to a variable for working the CURL commands.
#######
#TO-DO
#Need to put a dismantler/packager in for 5GB size limitation of object-cache storage.
#chmod needs fixed up.- probably not needed though
#Containers can only be 1 deep. Need to expand the script to fill directories/collections into swift metadata for sync and stage

# Changelog:
#2017-08-03: Using base code from "https://github.com/cookie33/irods-compound-resource/blob/master/scripts/univMSSInterface_gridftp.sh"
#2017-08-07: Integrated STAT command, as far as object-cache storage can anyway

VERSION=v0.2
PROG=`basename $0`
DEBUG=3
ID=$RANDOM
STATUS="OK"

# define logfile location
LOGFILE=/var/log/irods/univMSSInterface_SWIFT.log

#Curl Inputs for SWIFT
CURLCOMMAND=/usr/bin/curl
#Defining the SWIFT server (in our case, a proxy balancing across connections)
declare SWIFTSERVER="##REPLACE##"

####################################################
#Modified version of SURFsara's Keystone Auth script.
#Create a file in the script's working directory called "swiftauth.txt" with permissions to 700.
#As this is a 1 time thing, I did not incorporate it into the script.
#No sense wasting power checking/creating a file that should exist.
####################################################

tokencheck=$(((`date +%s` - `stat --format %Y swiftauth.txt`) <  (60*60*23) ))
if [ $tokencheck = 1 ]
	then
	#####################################################
	#This is where you will put your keystone information for SWIFT
	#This section is customizeable based upon the KeyStone setup.
	export OS_PROJECT_DOMAIN_NAME=Default
	export OS_USER_DOMAIN_NAME=Default
	export OS_PROJECT_NAME=##REPLACE##
	export OS_USERNAME=##REPLACE##
	export OS_PASSWORD=##REPLACE##
	export OS_AUTH_URL=##REPLACE##
	export OS_IDENTITY_API_VERSION=3

	#This section is the script provided by my SWIFT team for pulling a token
	JSONFILE=`mktemp`
	chmod 600 ${JSONFILE}

	TMPFILE=`mktemp`
	chmod 600 ${TMPFILE}

	cat >${JSONFILE} <<EOF
{
  "auth": {
	"identity": {
	   "methods": ["password"],
	  "password": {
		 "user": {
		"domain": {"name": "${OS_USER_DOMAIN_NAME}"},
		   "name": "${OS_USERNAME}",
		   "password": "${OS_PASSWORD}"
		 }
	  }
	   },
	   "scope": {
	  "project": {
		 "domain": {"name": "${OS_PROJECT_DOMAIN_NAME}"},
		"name": "${OS_PROJECT_NAME}"
	  }
	   }
   }
}

EOF

	curl -si  \
	-H "Content-Type: application/json" \
	-o ${TMPFILE} \
	-d @${JSONFILE} \
	${OS_AUTH_URL}/auth/tokens 2>/dev/null

	#Pulls the Auth Token from the temp file, grabs ONLY the token and trims the descriptors, then removes the end-of-line character.
	keystone=`cat ${TMPFILE} | grep 'X-Subject-Token:' | awk '{ print $2 }' | sed 's/.$//'`

	#Put's it into a txt file for something to check timestamps on to renew when needed. Also put's correct syntax into it.
	echo "X-Auth-Token: $keystone" > swiftauth.txt
	#Need to change this into a log entry###
	_log 2 tokenpull "Token was updated"
	rm -f ${TMPFILE} ${JSONFILE}

	#Our "token still good" else options.
else
	#This needs to become a proper log entry###
	_log 2 tokenpull "Token is still valid"
fi

############################
#CURL DEFINITIONS NEEDED HERE
AUTH=$(<swiftauth.txt)  #This one is pulled from the above token script. Changes every 24 hours (or if pulled earlier)
##############################
#THIS IS THE OBJECT STORAGE URL FOR THE IRODS ACCOUNT IN SWIFT.
#It can be found in teh same script that pulls our 24hour auth token, but remains static
URL="##REPLACE##"
#############################################
# functions to do the actions
#############################################

# function for the synchronization of file $1 on local disk resource to file $2 in the MSS
syncToArch () {
	# <your command or script to copy from cache to MSS> $1 $2
	# e.g: /usr/local/bin/rfcp $1 rfioServerFoo:$2
	# /bin/cp "$1" "$2"
	_log 2 syncToArch "entering syncToArch()=$*"

	#sourceFile=$1
	#destFile=$2

	# assign parameters and make sure a file with "," is copied
	# add "\" before a "," in the filename
	sourceFile=$(echo $1 | sed -e 's/,/\\,/g')
	destFile=$(echo $2 | sed -e 's/,/\\,/g')
	error=0

	if [ -s $1 ]
	then
		# so we have a NON-empty file. Copy it
		# Use curl to do transfers
		syncToArchCurl $sourceFile $destFile
		error=$?
	else
		_log 2 syncToArch "file \"$1\" is empty. Do not copy an empty file"
		error=1
	fi

	if [ $error != 0 ] # copy failure
	then
		STATUS="FAILURE"
	fi
	_log 2 syncToArch "The status is $error ($STATUS):"
	return $error
}


# function for staging a file $1 from the MSS to file $2 on disk
stageToCache () {
	# <your command to stage from MSS to cache> $1 $2
	# e.g: /usr/local/bin/rfcp rfioServerFoo:$1 $2
	_log 2 stageToCache "entering stageToCache()=$*"

	#sourceFile=$1
	#destFile=$2

	# assign parameters and make sure a file with "," is copied
	# add "\" before a "," in the filename
	sourceFile=$(echo $1 | sed -e 's/,/\\,/g')
	destFile=$(echo $2 | sed -e 's/,/\\,/g')
	error=0

	# Use Curl to do transfers
	stageToCacheCurl $sourceFile $destFile
	error=$?

	if [ $error != 0 ] # copy failure
	then
		STATUS="FAILURE"
	fi
	_log 2 stageToCache "The status is $error ($STATUS)"
	return $error
}


# function to create a new directory $1 in the MSS logical name space
mkdir () {
	# <your command to make a directory in the MSS> $1
	# e.g.: /usr/local/bin/rfmkdir -p rfioServerFoo:$1
	_log 2 mkdir "entering mkdir()=$*"

	destDir=$1
	error=0

	# Use curl make directory
	mkdirCurl $destDir
	error=$?

	if [ $error != 0 ] # mkdir failure
	then
		STATUS="FAILURE"
	fi
	_log 2 mkdir "The status is $error ($STATUS)"
	return $error
}


# function to modify ACLs $2 (octal) in the MSS logical name space for a given directory $1
chmod () {
	# <your command to modify ACL> $1 $2
	# e.g: /usr/local/bin/rfchmod $2 rfioServerFoo:$1
	_log 2 chmod "entering chmod()=$*"

	destFile=$1
	destAcl=$2
	error=0

	# Use curl to set ACL on file or directory
	chmodCurl $destFile  $destAcl
	error=$?

	if [ $error != 0 ] # chmod failure
	then
		STATUS="FAILURE"
	fi
	_log 2 chmod "The status is $error ($STATUS)"
	return $error
}


# function to remove a file $1 from the MSS
rm () {
	# <your command to remove a file from the MSS> $1
	# e.g: /usr/local/bin/rfrm rfioServerFoo:$1
	_log 2 rm "entering rm()=$*"

	#destFile=$1

	# assign parameters and make sure a file with "," is removed
	# add "\" before a "," in the filename
	destFile=$(echo $1 | sed -e 's/,/\\,/g')
	error=0

	# Use curl to remove a file
	rmCurl $destFile
	error=$?

	if [ $error != 0 ] # rm failure
	then
		STATUS="FAILURE"
	fi
	_log 2 rm "The status is $error ($STATUS)"
	return $error
}


# function to rename a file $1 into $2 in the MSS
mv () {
	   # <your command to rename a file in the MSS> $1 $2
	   # e.g: /usr/local/bin/rfrename rfioServerFoo:$1 rfioServerFoo:$2
	_log 2 mv "entering mv()=$*"

	#sourceFile=$1
	#destFile=$2

	# assign parameters and make sure a file with "," is moved
	# add "\" before a "," in the filename
	sourceFile=$(echo $1 | sed -e 's/,/\\,/g')
	destFile=$(echo $2 | sed -e 's/,/\\,/g')
	error=0

	# Use curl to move a file
	mvCurl $sourceFile $destFile
	error=$?

	if [ $error != 0 ] # mv failure
	then
		STATUS="FAILURE"
	fi
	_log 2 mv "The status is $error ($STATUS)"
	return $error
}


# function to do a stat on a file $1 stored in the MSS
stat () {
	# <your command to retrieve stats on the file> $1
	# e.g: output=`/usr/local/bin/rfstat rfioServerFoo:$1`
	_log 2 stat "entering stat()=$*"

	sourceFile=$(echo $1 | sed -e 's/,/\\,/g')
	error=0

	# Use curl to move a file
	statCurl $sourceFile
	error=$?

	if [ $error != 0 ] # stat failure
	then
		STATUS="FAILURE"
	fi
	_log 2 stat "The status is $error ($STATUS)"
	return $error
}


#############################################
# helper functions to do the actual actions
#############################################

_log() {
	TS=`date +"%Y:%m:%d-%T.%N "`
	level=$1; shift
	function=$1; shift
	if [ $level -lt $DEBUG ] ; then
		echo "$TS $ID $PROG[$$][$VERSION,$function,d${level}]: ${command}: $*" >>$LOGFILE 2>&1
	fi
}

syncToArchCurl () {
	# helper function curl
	# <your command or script to copy from cache to MSS> $1 $2
	# sourceFile=$1
	# destFile=$2

	error=0
	#Pull apart the source file path, but preserve directory structure
	meta=$(echo $1 | rev | cut -d '/' -f 2- | rev)
	#Keeps only the file name of the full path
	destFile=$(echo $1 | rev | cut -d '/' -f 1 | rev)
	_log 2 syncToArch "executing: $CURLCOMMAND -T $1 -X PUT -H \"$AUTH\" $URL/$2"
	status=$($CURLCOMMAND -T $1 -X PUT -H "$AUTH" $URL/$destFile   2>&1)
	error=$?

	if [ $error != 0 ] # syncToArch failure
	then
		_log 2 syncToArch "error-message: $status"
	fi
	metastat=$($CURLCOMMAND -X POST -H "$AUTH" $URL/$destFile -H "X-Object-Meta-Collection: $meta" 2>&1)
	error=$?

	if [ $error != 0 ] # syncToArch failure on meta data
	then
		_log 2 syncToArch "error-message: $metastat"
	fi
	
	
	return $error
}

stageToCacheCurl () {
	# helper function curl
	# <your command or script to copy from MSS to cache> $1 $2
	# sourceFile=$1
	# destFile=$2

	error=0

	_log 2 stageToCache "executing: $CURLCOMMAND -X GET -H \"$AUTH\" $URL/$1 -o $2"
	status=$($CURLCOMMAND -X GET -H "$AUTH" $URL/$1 -o $2  2>&1)
	error=$?

	if [ $error != 0 ] # stageToCache failure
	then
		_log 2 stageToCache "error-message: $status"
	fi

	return $error
}

mkdirCurl () {
	# helper function Curl
	# <your command to make a directory in the MSS> $1
	# destDir=$1

	# Use Curl to do transfers
	#Checking if it exists
	_log 2 mkdir "executing: $CURLCOMMAND -X GET -H \"$test\" $URL/$1"
	$CURLCOMMAND -X GET -H "$test" $URL/$1  > /dev/null 2>&1
	error=$?
	if [ $error = 0 ]
	then
		_log 2 mkdir "dir \"$1\" already exists. Not recreating directory."
	else
		# create the directory
		_log 2 mkdir "executing: $CURLCOMMAND -X PUT -H \"$AUTH\" $URL/$1"
		$CURLCOMMAND -X PUT -H "$AUTH" $URL/$1
		error=$?
	fi

	# we have a failure of the creation. Let's check if it really is a failure
	if [ $error != 0 ]
	then
		# check if the directory has been created properly
		_log 2 mkdir "Rechecking if dir \"$1\" already exists. There was a problem during the creation of the directory"
		$CURLCOMMAND -X GET -H "$test" $URL/$1  > /dev/null 2>&1
		error=$?
		if [ $error = 0 ]
		then
			_log 2 mkdir "dir \"$1\" was properly created. Probably a false error in iRODS/SWIFT"
		fi
	fi

	return $error
}

chmodCurl () {
	# helper function Curl
	# <your command to modify ACL> $1 $2
	# destFile=$1
	# destAcl=$2

	error=0

	# Use curl to do transfers
	_log 2 chmod "pseudo executing:  curl -X POST -H \"$test\" $URL/$1 -i -H \"X-Remove-Container-Read: \" -H \"X-Remove-Container-Write: \""
	_log 2 chmod "pseudo executing: iRODS makes it 700 anyway. It does not implement chmod for users"
	$CURLCOMMAND -X POST -H "$test" $URL/$1 -H "X-Remove-Container-Read: " -H "X-Remove-Container-Write:  "   2>&1
	error=$?

	return $error
}

rmCurl () {
	# helper function curl
	# <your command to remove file> $1
	# destFile=$1

	error=0

	# Use curl to do transfers
	_log 2 rm "executing: $CURLCOMMAND -X DELETE -H \"$AUTH\" $URL/$1"
	$CURLCOMMAND -X DELETE -H "$AUTH" $URL/$1  2>&1
	error=$?

	return $error
}

mvCurl () {
	# helper function curl
	# <your command to rename a file in the MSS> $1 $2
	#sourceFile=$1
	#destFile=$2

	error=0

	# Use curl to do transfers
	_log 2 mv "executing: $CURLCOMMAND -X COPY -H \"$AUTH\" -i $URL/$1 -H \"Destination: $2\""
	$CURLCOMMAND -X COPY -H "$AUTH" -i $URL/$1 -H "Destination: $2"  2>&1
	error=$?
	if [ $error != 0 ] # mv failure
	then
		_log 2 mv "executing: $CURLCOMMAND -X COPY -H \"$AUTH\" -i $URL/$1 -H \"Destination: $2\" failed"
	else
		_log 2 mv "executing: $CURLCOMMAND -X DELETE -H \"$AUTH\" $URL/$1"
		$CURLCOMMAND -X DELETE -H "$AUTH" $URL/$1 2>&1
		error=$?
	fi

	return $error
}

statCurl () {
	# helper function curl
	# <your command to stat a file in the MSS $1
	#sourceFile=$1

	error=0

	# Use curl to do transfers
	_log 2 stat "executing: $CURLCOMMAND -I -H \"$AUTH\" $URL/$1 | tr \'\\r\\n\' \' \'  "
	output=$( $CURLCOMMAND -I -H "$AUTH" $URL/$1 | tr '\r\n' ' ' 2>&1 )
	error=$?
	if [ $error != 0 ] # stat failure
	then
		_log 2 stat "executing: $CURLCOMMAND -I -H \"$AUTH\" $URL/$1 | tr \'\\r\\n\' \' \'"
	else
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
		device="0"
		inode="0"
		mode="0"
		nlink="0"
		uid_output="0"
		uid="0"
		gid_output="0"
		gid="0"
		devid="0"
		size=$(echo $output | awk '{print $7}')
		blksize="0"
		blkcnt="0"
		day=$(echo $output | awk '{print $12}')
		month=$(month=$(echo $output | awk '{print $13} ') ; awk -v "month=$month" 'BEGIN {months = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec"; printf "%02d", (index(months, month) + 3) / 4}')
		year=$(echo $output | awk '{ print $14}')
		hour=$(echo $output | awk '{print $15}' | tr ':' ' ' | awk '{print $1}')
		minute=$(echo $output | awk '{print $15}' | tr ':' ' ' | awk '{print $2}')
		second=$(echo $output | awk '{print $15}' | tr ':' ' ' | awk '{print $3}')
		ctime=$(echo "$year-$month-$day-$hour.$minute.$second")
		mtime=$ctime
		day=$(echo $output | awk '{print $27}')
		month=$(month=$(echo $output | awk '{print $28} ') ; awk -v "month=$month" 'BEGIN {months = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec"; printf "%02d", (index(months, month) + 3) / 4}')
		year=$(echo $output | awk '{ print $29}')
		hour=$(echo $output | awk '{print $30}' | tr ':' ' ' | awk '{print $1}')
		minute=$(echo $output | awk '{print $30}' | tr ':' ' ' | awk '{print $2}')
		second=$(echo $output | awk '{print $30}' | tr ':' ' ' | awk '{print $3}')
		atime=$(echo "$year-$month-$day-$hour.$minute.$second")
		echo "$device:$inode:$mode:$nlink:$uid:$gid:$devid:$size:$blksize:$blkcnt:$atime:$mtime:$ctime"

	fi

	return $error
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
