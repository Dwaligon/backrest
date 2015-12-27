#!/usr/bin/perl
####################################################################################################################################
# container.pl - Build docker containers for testing and documentation
####################################################################################################################################

####################################################################################################################################
# Perl includes
####################################################################################################################################
use strict;
use warnings FATAL => qw(all);
use Carp qw(confess longmess);

# Convert die to confess to capture the stack trace
$SIG{__DIE__} = sub { Carp::confess @_ };

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use Getopt::Long qw(GetOptions);
use Scalar::Util qw(blessed);
# use Cwd qw(abs_path);
# use Pod::Usage qw(pod2usage);
# use Scalar::Util qw(blessed);

use lib dirname($0) . '/../lib';
use BackRest::Common::Ini;
# use BackRest::Common::Ini;
use BackRest::Common::Log;
use BackRest::FileCommon;
# use BackRest::Db;

use lib dirname($0) . '/lib';
use BackRestTest::Common::ExecuteTest;
# use BackRestTest::CommonTest;
# use BackRestTest::CompareTest;
# use BackRestTest::ConfigTest;
# use BackRestTest::FileTest;
# use BackRestTest::HelpTest;

####################################################################################################################################
# Usage
####################################################################################################################################

=head1 NAME

container.pl - Docker Container Build

=head1 SYNOPSIS

container.pl [options]

 Build Options:
   --os                 os to build (defaults to all)

 Configuration Options:
   --log-level          log level to use for tests (defaults to info)
   --quiet, -q          equivalent to --log-level=off

 General Options:
   --version            display version and exit
   --help               display usage and exit
=cut

####################################################################################################################################
# Command line parameters
####################################################################################################################################
my $strLogLevel = 'info';
my $bVersion = false;
my $bHelp = false;
my $bQuiet = false;

GetOptions ('q|quiet' => \$bQuiet,
            'version' => \$bVersion,
            'help' => \$bHelp,
            'log-level=s' => \$strLogLevel)
    or pod2usage(2);

# Display version and exit if requested
if ($bVersion || $bHelp)
{
    syswrite(*STDOUT, 'pgBackRest ' . BACKREST_VERSION . " Docker Container Build\n");

    if ($bHelp)
    {
        syswrite(*STDOUT, "\n");
        pod2usage();
    }

    exit 0;
}

if (@ARGV > 0)
{
    syswrite(*STDOUT, "invalid parameter\n\n");
    pod2usage();
}

####################################################################################################################################
# Setup
####################################################################################################################################
# Set a neutral umask so tests work as expected
umask(0);

# Set console log level
if ($bQuiet)
{
    $strLogLevel = 'off';
}

logLevelSet(undef, uc($strLogLevel));

# Create temp path
my $strTempPath = dirname(abs_path($0)) . '/vm/docker';

if (!-e $strTempPath)
{
    mkdir $strTempPath
        or confess &log(ERROR, "unable to create ${strTempPath}");
}

####################################################################################################################################
# Valid OS list
####################################################################################################################################
my @stryOS =
(
    'co6',                              # CentOS 6
    # 'co7',                              # CentOS 7
    # 'u12',                              # Ubuntu 12.04
    'u14'                               # Ubuntu 14.04
);

use constant TEST_GROUP                                             => 'admin';
use constant TEST_GROUP_ID                                          => 6000;
use constant TEST_USER                                              => 'vagrant';
use constant TEST_USER_ID                                           => TEST_GROUP_ID;

use constant POSTGRES_GROUP                                         => 'postgres';
use constant POSTGRES_GROUP_ID                                      => 5000;
use constant POSTGRES_USER                                          => POSTGRES_GROUP;
use constant POSTGRES_USER_ID                                       => POSTGRES_GROUP_ID;

use constant BACKREST_GROUP                                         => POSTGRES_GROUP;
use constant BACKREST_GROUP_ID                                      => POSTGRES_GROUP_ID;
use constant BACKREST_USER                                          => 'backrest';
use constant BACKREST_USER_ID                                       => 5001;

####################################################################################################################################
# User/group creation
####################################################################################################################################
sub groupCreate
{
    my $strOS = shift;
    my $strName = shift;
    my $iId = shift;

    return "RUN groupadd -g${iId} ${strName}";
}

sub userCreate
{
    my $strOS = shift;
    my $strName = shift;
    my $iId = shift;
    my $strGroup = shift;

    if ($strOS eq 'co6')
    {
        return "RUN adduser -g${strGroup} -u${iId} -n ${strName}";
    }
    elsif ($strOS eq 'u14')
    {
        return "RUN adduser --uid=${iId} --ingroup=${strGroup} --disabled-password --gecos \"\" ${strName}";
    }

    confess &log(ERROR, "unable to create user for os '${strOS}'");
}

sub postgresUserCreate
{
    my $strOS = shift;

    return "# Create PostgreSQL user/group\n" .
           groupCreate($strOS, POSTGRES_GROUP, POSTGRES_GROUP_ID) . "\n" .
           userCreate($strOS, POSTGRES_USER, POSTGRES_USER_ID, POSTGRES_GROUP);
}

sub backrestUserCreate
{
    my $strOS = shift;

    return "# Create BackRest user/group\n" .
           groupCreate($strOS, BACKREST_GROUP, BACKREST_GROUP_ID) . "\n" .
           userCreate($strOS, BACKREST_USER, BACKREST_USER_ID, BACKREST_GROUP);
}

####################################################################################################################################
# Create pg_backrest.conf
####################################################################################################################################
sub backrestConfigCreate
{
    my $strOS = shift;
    my $strUser = shift;
    my $strGroup = shift;

    return "# Create pg_backrest.conf\n" .
           "RUN touch /etc/pg_backrest.conf\n" .
           "RUN chmod 640 /etc/pg_backrest.conf\n" .
           "RUN chown ${strUser}:${strGroup} /etc/pg_backrest.conf";
}

####################################################################################################################################
# Setup SSH
####################################################################################################################################
sub sshSetup
{
    my $strOS = shift;
    my $strUser = shift;
    my $strGroup = shift;

    return "# Setup SSH\n" .
           "RUN mkdir /home/${strUser}/.ssh\n" .
           "COPY id_rsa  /home/${strUser}/.ssh/id_rsa\n" .
           "COPY id_rsa.pub  /home/${strUser}/.ssh/authorized_keys\n" .
           "RUN chown -R ${strUser}:${strGroup} /home/${strUser}/.ssh\n" .
           "RUN chmod 700 /home/${strUser}/.ssh\n" .
           "RUN echo 'Host *' > /home/${strUser}/.ssh/config\n" .
           "RUN echo '    StrictHostKeyChecking no' >> /home/${strUser}/.ssh/config\n" .
           "RUN echo '    LogLevel quiet' >> /home/${strUser}/.ssh/config";
}

####################################################################################################################################
# Repo Setup
####################################################################################################################################
sub repoSetup
{
    my $strOS = shift;
    my $strUser = shift;
    my $strGroup = shift;

    return "# Setup repository\n" .
           "RUN mkdir /var/lib/backrest\n" .
           "RUN chown -R ${strUser}:${strGroup} /var/lib/backrest\n" .
           "RUN chmod 750 /var/lib/backrest";
}

####################################################################################################################################
# Build containers
####################################################################################################################################
eval
{
    # Create SSH key (if it does not already exist)
    if (-e "${strTempPath}/id_rsa")
    {
        &log(INFO, "SSH key already exists");
    }
    else
    {
        &log(INFO, "Building SSH keys...");

        executeTest("ssh-keygen -f ${strTempPath}/id_rsa -t rsa -b 768 -N ''");
    }

    foreach my $strOS (@stryOS)
    {
        my $strImage;
        my $strImageName;

        # Base image
        ###########################################################################################################################
        $strImageName = "${strOS}-base";
        &log(INFO, "Building ${strImageName} image...");

        $strImage = "# Base Container\nFROM ";

        if ($strOS eq 'co6')
        {
            $strImage .= 'centos:6.7';
        }
        elsif ($strOS eq 'u14')
        {
            $strImage .= 'ubuntu:14.04';
        }

        # Intall SSH
        $strImage .= "\n\n# Install SSH\n";

        if ($strOS eq 'co6')
        {
            $strImage .= 'RUN yum -y install openssh-server openssh-clients';
        }
        elsif ($strOS eq 'u14')
        {
            $strImage .= 'RUN apt-get -y install openssh-server';
        }

        # Add PostgreSQL packages
        $strImage .= "\n\n# Add PostgreSQL packages\n";

        if ($strOS eq 'co6')
        {
            $strImage .= 'RUN rpm -ivh http://yum.postgresql.org/9.4/redhat/rhel-6-x86_64/pgdg-centos94-9.4-1.noarch.rpm'
        }
        elsif ($strOS eq 'u14')
        {
            $strImage .=
                "RUN echo 'deb http://apt.postgresql.org/pub/repos/apt/ trusty-pgdg main 9.5' >> /etc/apt/sources.list.d/pgdg.list\n" .
                "RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -\n" .
                "RUN sudo apt-get update";
        }

        # Create test group
        $strImage .=
            "\n\n# Create test group\n" .
            groupCreate($strOS, TEST_GROUP, TEST_GROUP_ID) . "\n";

        if ($strOS eq 'co6')
        {
            $strImage .=
                "RUN yum -y install sudo\n" .
                "RUN echo '%" . TEST_GROUP . "        ALL=(ALL)       NOPASSWD: ALL' > /etc/sudoers.d/" . TEST_GROUP . "\n" .
                "RUN sed -i 's/^Defaults    requiretty\$/\\# Defaults    requiretty/' /etc/sudoers";
        }
        elsif ($strOS eq 'u14')
        {
            $strImage .=
                "RUN sed -i 's/^\\\%admin.*\$/\\\%" . TEST_GROUP . " ALL\\=\\(ALL\\) NOPASSWD\\: ALL/' /etc/sudoers";
        }

        # Create test user
        $strImage .=
            "\n\n# Create test user\n" .
            userCreate($strOS, TEST_USER, TEST_USER_ID, TEST_GROUP);

        # Suppress dpkg interactive output
        if ($strOS eq 'u14')
        {
            $strImage .=
                "\n\n# Suppress dpkg interactive output\n" .
                "RUN rm /etc/apt/apt.conf.d/70debconf";
        }

        # Start SSH when container starts
        $strImage .=
            "\n\n# Start SSH when container starts\n" .
            "ENTRYPOINT service ssh restart && bash\n";

        # Write the image
        fileStringWrite("${strTempPath}/${strImageName}", $strImage, false);
        executeTest("docker build -f ${strTempPath}/${strImageName} -t backrest/${strImageName} ${strTempPath}");

        # Db image
        ###########################################################################################################################
        $strImageName = "${strOS}-db";
        &log(INFO, "Building ${strImageName} image...");

        $strImage = "# Database Container\nFROM backrest/${strOS}-base";

        # Create PostgreSQL User
        $strImage .= "\n\n" . postgresUserCreate($strOS);

        # Install SSH key
        $strImage .=
            "\n\n" . sshSetup($strOS, POSTGRES_USER, POSTGRES_GROUP);

        # Create pg_backrest.conf
        $strImage .=
            "\n\n" . backrestConfigCreate($strOS, POSTGRES_USER, POSTGRES_GROUP);

        # Install PostgreSQL
        $strImage .=
            "\n\n# Install PostgreSQL\n";

        if ($strOS eq 'co6')
        {
            $strImage .=
                "RUN yum -y install postgresql94-server";
        }
        elsif ($strOS eq 'u14')
        {
            $strImage .=
                "RUN apt-get install -y postgresql-9.4\n" .
                "RUN pg_dropcluster --stop 9.4 main";
        }

        # Write the image
        fileStringWrite("${strTempPath}/${strImageName}", "${strImage}\n", false);
        executeTest("docker build -f ${strTempPath}/${strImageName} -t backrest/${strImageName} ${strTempPath}");

        # Backup image
        ###########################################################################################################################
        $strImageName = "${strOS}-backup";
        &log(INFO, "Building ${strImageName} image...");

        $strImage = "# Database Container\nFROM backrest/${strOS}-base";

        # Create BackRest User
        $strImage .= "\n\n" . backrestUserCreate($strOS);

        # Install SSH key
        $strImage .=
            "\n\n" . sshSetup($strOS, BACKREST_USER, BACKREST_GROUP);

        # Create pg_backrest.conf
        $strImage .=
            "\n\n" . backrestConfigCreate($strOS, BACKREST_USER, BACKREST_GROUP);

        # Setup repository
        $strImage .=
            "\n\n" . repoSetup($strOS, BACKREST_USER, BACKREST_GROUP);

        # Install Perl packages
        $strImage .=
            "\n\n# Install Perl packages\n";

        if ($strOS eq 'co6')
        {
            $strImage .=
                "RUN yum -y install perl perl-Time-HiRes perl-parent perl-JSON perl-Digest-SHA perl-DBD-Pg";
        }
        elsif ($strOS eq 'u14')
        {
            $strImage .=
                "RUN apt-get -y install libdbd-pg-perl libdbi-perl libnet-daemon-perl libplrpc-perl";
        }

        # Write the image
        fileStringWrite("${strTempPath}/${strImageName}", "${strImage}\n", false);
        executeTest("docker build -f ${strTempPath}/${strImageName} -t backrest/${strImageName} ${strTempPath}");
    }
};

if ($@)
{
    my $oMessage = $@;

    # If a backrest exception then return the code - don't confess
    if (blessed($oMessage) && $oMessage->isa('BackRest::Common::Exception'))
    {
        syswrite(*STDOUT, $oMessage->trace());
        exit $oMessage->code();
    }

    syswrite(*STDOUT, $oMessage);
    exit 255;;
}
