# irods-swift
iRODS Swift &amp; Keystone Compound Resource
Steps on using a UnivMSS Resource to link iRODS to a Swift cluster that uses Keystone Authentication 

Made this because Keystone Authentication seems to break S3 plugins all over.

Initial Setup:
Create a file for our keystone token to be stored in, also letting us track the 24hour lifetime:

touch /var/lib/irods/iRODS/server/bin/cmd/swiftauth.txt
chmod 600 /var/lib/irods/iRODS/server/bin/cmd/swiftauth.txt

First: Creating resources:

iadmin mkresc swiftCompResc compound "auto_repl=off"
iadmin mkresc swiftCacheResc unixfilesystem <host>:<cachePath> "swift cache resource"
iadmin mkresc swiftObjectResc univmss
iadmin modresc swiftObjResc context "univMSSInterface_swift.sh"
iadmin addchildtoresc swiftCompResc swiftCacheResc cache
iadmin addchildtoresc swiftCompResc swiftObjResc archive

Double check the work is good:
ilsresc -l swiftCompResc

Second: Put the univMSSInterface_swift.sh into iRODS

cp univMSSInterface_swift.sh /var/lib/irods/iRODS/server/bin/cmd/




