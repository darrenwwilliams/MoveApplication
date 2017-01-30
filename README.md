# MoveApplication
Swift source to move a Mac application to the Applications folder instead of requiring users to drag the application manually. Reduces issues for the end user.

Requirements
------------
Tested on MacOS 10.11 or higher. Any macOS running Swift 3.0.1 should be supported.

Note that this code also uses a global logger object so you can simply replace the logger calls with "print" if you dont use a logging framework.

Usage
-----

Copy the swift file to your application and link to the DiskArbitration framework.

Call the main entry point as

- MoveApplication.toApplicationsFolder()

from your applicationWillFinishLaunching function and that is all that is required. We suggest you wrap this in an #if statement so it only executes in your release copy.

References
-------
This work was inspired by the great work started with the LetsMove framework based on Objective C from https://github.com/potionfactory/LetsMove.

License
-------
Public domain

Version History
---------------

* 1.00
	- Initial release for Swift 3.0 and support for macOS Sierra and earlier
	
Contributors:
-------------
* Darren Williams
