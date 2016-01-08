# pgBackRest - Regression, Unit, & Integration Testing

## Introduction

pgBackRest uses Docker to run tests and generate documentation. Docker's light-weight virualization provides the a good balance between proper OS emulation and performance (especially startup)

A Vagrantfile is provided that contains the complete configuration required to run pgBackRest tests and build documentation. If Vagrant is not suitable then the Vagrantfile still contains the configuration steps required to build a test system.

Note that this is not required for normal operation of pgBackRest.

## Testing

The easiest way to start testing pgBackRest is with the included Vagrantfile.

Build Vagrant and Logon:
```
cd test
vagrant up
vagrant ssh
```
The `vagrant up` step could take some time as a number of Docker containers must also be built. The `vagrant up` command automatically logs onto the VM.

Run All Tests:
```
/backrest/test/test.pl
```

Run Tests for a Specific OS:
```
/backrest/test/test.pl --vm=co6
```

Run Tests for a Specific OS and Module:
```
/backrest/test/test.pl --vm=co6 --module=backup
```

Run Tests for a Specific OS, Module, and Test:
```
/backrest/test/test.pl --vm=co6 --module=backup --full
```

Run Tests for a Specific OS, Module, Test, and Thread Max:
```
/backrest/test/test.pl --vm=co6 --module=backup --full --thread-max=4
```
Note that thread-max is only applicable to the `synthetic` and full tests in the `backup` module.
