# irods-swift
iRODS Swift &amp; Keystone Compound Resource
Steps on using a UnivMSS Resource to link iRODS to a Swift cluster that uses Keystone Authentication 

Made this because Keystone Authentication seems to break S3 plugins all over.


First: Creating resources.
iadmin mkresc swiftCompResc compound "auto_repl=off"
iadmin mkresc swiftCacheResc unixfilesystem <host>:<cachePath> "swift cache resource"
iadmin mkresc swiftObjectResc univmss
